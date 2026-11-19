/**
 * @Class Name    : OneCall24ApiService
 * @Author        : Devesh Sharma
 * @Purpose       : Manages the OneCall24 API integration process.
 * @Description   : Handles API result processing, candidate
 *                  synchronization, response parsing and
 *                  Salesforce record operations.
 */

public class OneCall24ApiService {
    
    // GET Results API and Save Candidates
    public static void fetchResults() {
        try {
            // 1. Fetch candidates from OneCall24
            HttpResponse response = OneCall24ApiClient.getResults();
            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();
            
            System.debug('GET STATUS: ' + statusCode);
            System.debug('GET RESPONSE: ' + responseBody);

            // 2. Handle API Failure
            if (statusCode < 200 || statusCode >= 300) {
                Boolean retryable = OneCall24ExceptionHandler.isRetryableStatusCode(statusCode);
                OneCall24Helper.saveErrorLogs( new List<OneCall24_Error_Log__c>{OneCall24Helper.createErrorLog(
                 null,'/results','GET /results',statusCode,'API Failure','GET API returned HTTP status ' + statusCode,responseBody,
                    retryable ? 'Pending' : 'Not Required')
                    }
                );
                return;
            }

            // 3. Parse API Response
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> apiRecords = (List<Object>) responseMap.get('records');
            
            if (apiRecords == null || apiRecords.isEmpty()) {
                System.debug('No candidates received.');
                return;
            }
            
            List<Screening_Result__c> recordsToUpsert = new List<Screening_Result__c>();
            List<String> refsToUpsert = new List<String>();
            Set<String> processedRefs = new Set<String>();
            List<OneCall24_Error_Log__c> errorLogs = new List<OneCall24_Error_Log__c>();

            // 4. Map Candidate Records
            for (Object item : apiRecords) {Map<String, Object> candidate = (Map<String, Object>) item;
                String candidateRef = OneCall24Helper.getString(candidate, 'ref');
                                            
                if (String.isBlank(candidateRef)) {
                    errorLogs.add(OneCall24Helper.createErrorLog(null,'/results','GET /results - Mapping', null, 'Record Failure',
                    'Candidate reference is missing.',JSON.serialize(candidate),'Failed'));
                    continue;
                }
                if (processedRefs.contains(candidateRef)) {
                    continue;
                }
                processedRefs.add(candidateRef);
                                            
                try {
                    Screening_Result__c sr = new Screening_Result__c();
                    sr.External_Reference__c = candidateRef;
                    sr.Salesforce_Contact_Id__c = OneCall24Helper.getString(candidate, 'salesforce_contact_id');
                    sr.First_Name__c = OneCall24Helper.getString(candidate, 'first_name');
                    sr.Last_Name__c = OneCall24Helper.getString(candidate, 'last_name');
                    sr.Mobile__c = OneCall24Helper.getString(candidate, 'mobile');
                    sr.Email__c = OneCall24Helper.getString(candidate, 'email');
                    sr.Status__c = OneCall24Helper.getString(candidate, 'status');
                    sr.Outcome__c = OneCall24Helper.getString(candidate, 'outcome');
                    sr.Interested__c = OneCall24Helper.getString(candidate, 'interested');
                    sr.Right_To_Work__c = OneCall24Helper.getString(candidate, 'right_to_work');
                    sr.Visa_Valid__c = OneCall24Helper.getString(candidate, 'visa_valid');
                    sr.AI_Comments__c = OneCall24Helper.getString(candidate, 'ai_comments');
                    sr.Care_Experience_Months__c = OneCall24Helper.getDecimal(candidate, 'care_experience_months');
                    sr.Job_Title__c = OneCall24Helper.getString(candidate, 'job_title');
                    sr.Shift_Pattern__c = OneCall24Helper.getString(candidate, 'shift_pattern');
                    sr.Shifts_Per_Week__c = OneCall24Helper.getDecimal(candidate, 'shifts_per_week');
                    sr.Postcode__c = OneCall24Helper.getString(candidate, 'postcode');
                    sr.Travel_Distance__c = OneCall24Helper.getString(candidate, 'travel_distance');
                    sr.Driving_Licence__c = OneCall24Helper.getString(candidate, 'driving_licence');
                    sr.Car_Access__c = OneCall24Helper.getString(candidate, 'car_access');
                    sr.Call_Count__c = OneCall24Helper.getDecimal(candidate, 'call_count');
                    sr.Last_Call_At__c = OneCall24Helper.getDateTime(candidate, 'last_call_at');
                    sr.Updated_At__c = OneCall24Helper.getDateTime(candidate, 'updated_at');

                    recordsToUpsert.add(sr);
                    refsToUpsert.add(candidateRef);

                } catch (Exception ex) {
                    errorLogs.add(OneCall24Helper.createErrorLog(
                       candidateRef,'/results','GET /results - Mapping',null,'Record Failure',
                        ex.getMessage(),JSON.serialize(candidate),'Failed'));
                }
            }

            // 5. Save Mapping Errors
            OneCall24Helper.saveErrorLogs(errorLogs);
            
            if (recordsToUpsert.isEmpty()) {
                System.debug('No valid candidates for upsert.');
                return;
            }

            // 6. Upsert Salesforce Records
            Database.UpsertResult[] results = Database.upsert(recordsToUpsert,Screening_Result__c.External_Reference__c,false);
            List<String> successfulRefs = new List<String>();
            errorLogs.clear();

            // 7. Process Upsert Results
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    successfulRefs.add(refsToUpsert[i]);
                } else {
                    for (Database.Error err : results[i].getErrors()) {
                        errorLogs.add( OneCall24Helper.createErrorLog( refsToUpsert[i],'/results',
                        'Salesforce Upsert', null,'Record Failure', err.getMessage(),null,'Retry Scheduled' ));
                    }
                }
            }

            // 8. Save DML Errors
            OneCall24Helper.saveErrorLogs(errorLogs);

            // 9. Resolve Old Errors and Confirm Candidates
            if (!successfulRefs.isEmpty()) {
                OneCall24Helper.resolveErrorLogs(successfulRefs);
                System.enqueueJob( new ConfirmCandidatesJob(successfulRefs));
            }

            System.debug('RECEIVED: ' + apiRecords.size());
            System.debug('SUCCESS: ' + successfulRefs.size());
            System.debug('FAILED: ' + (recordsToUpsert.size() - successfulRefs.size()));
        } catch (CalloutException ex) {
            OneCall24ExceptionHandler.handleCalloutException(ex,'GET /results','/results',null);
        } catch (Exception ex) {
            OneCall24ExceptionHandler.handleException(ex,'GET /results','/results', null);
        }
    }

    // POST Reset API
    public static void resetConfirmations() {
        try {
            
            HttpResponse response = OneCall24ApiClient.resetConfirmations();
            Integer statusCode = response.getStatusCode();
            System.debug(LoggingLevel.INFO,'OneCall24 RESET API | HTTP Status: ' + statusCode);
            
            if (statusCode < 200 || statusCode >= 300) {
                Boolean retryable = OneCall24ExceptionHandler.isRetryableStatusCode(statusCode);
                OneCall24Helper.saveErrorLogs( new List<OneCall24_Error_Log__c>{
                        OneCall24Helper.createErrorLog(null,'/reset','POST /reset',statusCode,'API Failure',
                            'Reset API returned HTTP status ' + statusCode, response.getBody(),retryable ? 'Pending' : 'Not Required')});
            }
             System.debug(LoggingLevel.INFO,'OneCall24 RESET API Response: ' + response.getBody());
            
        } catch (CalloutException ex) {
            OneCall24ExceptionHandler.handleCalloutException(ex,'POST /reset','/reset',null);
        } catch (Exception ex) {
            OneCall24ExceptionHandler.handleException( ex,'POST /reset','/reset',null);
        }
    }
}