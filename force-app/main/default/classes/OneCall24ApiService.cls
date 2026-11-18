public class OneCall24ApiService {

    private static final String RESULTS_ENDPOINT =
        'callout:OneCall24_API/results?limit=200';

    public static void fetchResults() {

        List<OneCall24_Error_Log__c> errorLogs =
            new List<OneCall24_Error_Log__c>();

        try {
            Http http = new Http();
            HttpRequest request = new HttpRequest();

            request.setEndpoint(RESULTS_ENDPOINT);
            request.setMethod('GET');
            request.setTimeout(120000);

            HttpResponse response = http.send(request);
            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();

            System.debug('GET STATUS: ' + statusCode);
            System.debug('GET RESPONSE: ' + responseBody);

           
            // API failure handling
            if (statusCode < 200 || statusCode >= 300) {
                
                Boolean shouldRetry = (statusCode == 500);
                
                errorLogs.add(createErrorLog(
                    null,
                    RESULTS_ENDPOINT,
                    'GET /results',
                    statusCode,
                    'API Failure',
                    'GET API returned HTTP status ' + statusCode,
                    responseBody,
                    shouldRetry ? 'Pending' : 'Not Required'
                ));
                
                saveErrorLogs(errorLogs);
                
                return;
            }


            Map<String, Object> responseMap =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);

            List<Object> apiRecords =
                (List<Object>) responseMap.get('records');

            if (apiRecords == null || apiRecords.isEmpty()) {
                System.debug('No candidates received from OneCall24.');
                return;
            }

            List<Screening_Result__c> recordsToUpsert =
                new List<Screening_Result__c>();

            List<String> refsToUpsert = new List<String>();

            Set<String> processedRefs = new Set<String>();

            for (Object item : apiRecords) {

                Map<String, Object> candidate =
                    (Map<String, Object>) item;

                String candidateRef =
                    getString(candidate, 'ref');

                if (String.isBlank(candidateRef)) {

                    errorLogs.add(createErrorLog(
                        null,
                        RESULTS_ENDPOINT,
                        'GET /results - Mapping',
                        null,
                        'Record Failure',
                        'Candidate reference is missing.',
                        JSON.serialize(candidate),
                        'Failed'
                    ));

                    continue;
                }

                if (processedRefs.contains(candidateRef)) {
                    continue;
                }

                processedRefs.add(candidateRef);

                try {

                    Screening_Result__c sr =
                        new Screening_Result__c();

                    sr.External_Reference__c = candidateRef;

                    sr.Salesforce_Contact_Id__c =
                        getString(candidate, 'salesforce_contact_id');

                    sr.First_Name__c =
                        getString(candidate, 'first_name');

                    sr.Last_Name__c =
                        getString(candidate, 'last_name');

                    sr.Mobile__c =
                        getString(candidate, 'mobile');

                    sr.Email__c =
                        getString(candidate, 'email');

                    sr.Status__c =
                        getString(candidate, 'status');

                    sr.Outcome__c =
                        getString(candidate, 'outcome');

                    sr.Interested__c =
                        getString(candidate, 'interested');

                    sr.Right_To_Work__c =
                        getString(candidate, 'right_to_work');

                    sr.Visa_Valid__c =
                        getString(candidate, 'visa_valid');

                    sr.AI_Comments__c =
                        getString(candidate, 'ai_comments');

                    sr.Care_Experience_Months__c =
                        getDecimal(candidate, 'care_experience_months');

                    sr.Job_Title__c =
                        getString(candidate, 'job_title');

                    sr.Shift_Pattern__c =
                        getString(candidate, 'shift_pattern');

                    sr.Shifts_Per_Week__c =
                        getDecimal(candidate, 'shifts_per_week');

                    sr.Postcode__c =
                        getString(candidate, 'postcode');

                    sr.Travel_Distance__c =
                        getString(candidate, 'travel_distance');

                    sr.Driving_Licence__c =
                        getString(candidate, 'driving_licence');

                    sr.Car_Access__c =
                        getString(candidate, 'car_access');

                    sr.Call_Count__c =
                        getDecimal(candidate, 'call_count');

                    sr.Last_Call_At__c =
                        getDateTime(candidate, 'last_call_at');

                    sr.Updated_At__c =
                        getDateTime(candidate, 'updated_at');

                    recordsToUpsert.add(sr);
                    refsToUpsert.add(candidateRef);

                } catch (Exception mappingException) {

                    errorLogs.add(createErrorLog(
                        candidateRef,
                        RESULTS_ENDPOINT,
                        'GET /results - Mapping',
                        null,
                        'Record Failure',
                        mappingException.getMessage(),
                        JSON.serialize(candidate),
                        'Failed'
                    ));
                }
            }

            // Save mapping errors.
            saveErrorLogs(errorLogs);
            errorLogs.clear();

            if (recordsToUpsert.isEmpty()) {
                System.debug('No valid candidates available for upsert.');
                return;
            }

         
            Database.UpsertResult[] results =
                Database.upsert(
                    recordsToUpsert,
                    Screening_Result__c.External_Reference__c,
                    false
                );

            List<String> refsToConfirm = new List<String>();

            for (Integer i = 0; i < results.size(); i++) {

                if (results[i].isSuccess()) {

                    refsToConfirm.add(refsToUpsert[i]);

                    System.debug(
                        'UPSERT SUCCESS: ' + refsToUpsert[i]
                    );

                } else {

                    String errorMessage = '';

                    for (Database.Error err : results[i].getErrors()) {

                        errorMessage +=
                            'Status: ' + err.getStatusCode() +
                            ' | Message: ' + err.getMessage() +
                            ' | Fields: ' + String.join(err.getFields(), ',') +
                            ' || ';
                    }

                    errorLogs.add(createErrorLog(
                        refsToUpsert[i],
                        RESULTS_ENDPOINT,
                        'Salesforce Upsert',
                        null,
                        'Record Failure',
                        errorMessage,
                        null,
                        'Retry Scheduled'
                    ));

                    System.debug(
                        'UPSERT FAILED: ' + refsToUpsert[i] +
                        ' | ' + errorMessage
                    );
                }
            }

            saveErrorLogs(errorLogs);

            if (!refsToConfirm.isEmpty()) {
                resolveErrorLogs(refsToConfirm);
            }

            // Only successfully saved records are confirmed.
            if (!refsToConfirm.isEmpty()) {

                System.enqueueJob(
                    new ConfirmCandidatesJob(refsToConfirm)
                );
            }

            System.debug('API RECORDS RECEIVED: ' + apiRecords.size());
            System.debug('UPSERT SUCCESS COUNT: ' + refsToConfirm.size());
            System.debug(
                'UPSERT FAILURE COUNT: ' +
                (recordsToUpsert.size() - refsToConfirm.size())
            );

        } catch (Exception ex) {

            errorLogs.add(createErrorLog(
                null,
                RESULTS_ENDPOINT,
                'GET /results',
                null,
                'Exception',
                ex.getMessage() +
                ' | Line Number: ' + ex.getLineNumber(),
                null,
                'Retry Scheduled'
            ));

            saveErrorLogs(errorLogs);

            System.debug(
                'OneCall24 API SERVICE EXCEPTION: ' +
                ex.getMessage() +
                ' | Line: ' + ex.getLineNumber()
            );
        }
    }

    // ---------------- HELPER METHODS ----------------

    private static String getString(
        Map<String, Object> data,
        String key
    ) {
        Object value = data.get(key);

        return value == null ? null : String.valueOf(value);
    }

    private static Decimal getDecimal(
        Map<String, Object> data,
        String key
    ) {
        Object value = data.get(key);

        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }

        return Decimal.valueOf(String.valueOf(value));
    }

    private static Datetime getDateTime(
        Map<String, Object> data,
        String key
    ) {
        Object value = data.get(key);

        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }

        return (Datetime) JSON.deserialize(
            JSON.serialize(String.valueOf(value)),
            Datetime.class
        );
    }

    private static OneCall24_Error_Log__c createErrorLog(
        String candidateRef,
        String endpoint,
        String operation,
        Integer statusCode,
        String errorType,
        String errorMessage,
        String responseBody,
        String retryStatus
    ) {

        OneCall24_Error_Log__c logRecord =
            new OneCall24_Error_Log__c();

        logRecord.Candidate_Reference__c =
            truncateText(candidateRef, 100);

        logRecord.API_Endpoint__c =
            truncateText(endpoint, 255);

        logRecord.Operation__c =
            truncateText(operation, 100);

        logRecord.HTTP_Status_Code__c = statusCode;

        logRecord.Error_Type__c = errorType;

        logRecord.Error_Message__c =
            truncateText(errorMessage, 32000);

        logRecord.Response_Body__c =
            truncateText(responseBody, 32000);

        logRecord.Occurred_At__c = System.now();

        logRecord.Retry_Status__c = retryStatus;

        return logRecord;
    }

    private static void saveErrorLogs(
        List<OneCall24_Error_Log__c> logs
    ) {

        if (logs == null || logs.isEmpty()) {
            return;
        }

        Database.SaveResult[] saveResults =
            Database.insert(logs, false);

        for (Integer i = 0; i < saveResults.size(); i++) {

            if (!saveResults[i].isSuccess()) {

                for (Database.Error err : saveResults[i].getErrors()) {

                    System.debug(
                        'ERROR LOG INSERT FAILED: ' +
                        err.getMessage()
                    );
                }
            }
        }
    }

    private static void resolveErrorLogs(List<String> refs) {

        if (refs == null || refs.isEmpty()) {
            return;
        }

        List<OneCall24_Error_Log__c> oldLogs = [
            SELECT Id, Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c IN :refs
            AND Retry_Status__c IN (
                'Pending',
                'Retry Scheduled',
                'Retrying'
            )
        ];

        for (OneCall24_Error_Log__c logRecord : oldLogs) {
            logRecord.Retry_Status__c = 'Success';
        }

        if (!oldLogs.isEmpty()) {
            Database.update(oldLogs, false);
        }
    }

    private static String truncateText(
        String value,
        Integer maxLength
    ) {

        if (value == null) {
            return null;
        }

        return value.length() > maxLength
            ? value.substring(0, maxLength)
            : value;
    }
    
    
public static void resetConfirmations() {

    String endpoint = 'callout:OneCall24_API/reset';

    try {

        Http http = new Http();
        HttpRequest request = new HttpRequest();

        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setTimeout(120000);

        HttpResponse response = http.send(request);

        Integer statusCode = response.getStatusCode();
        String responseBody = response.getBody();

        System.debug('RESET STATUS: ' + statusCode);
        System.debug('RESET RESPONSE: ' + responseBody);

        if (statusCode < 200 || statusCode >= 300) {

            List<OneCall24_Error_Log__c> logs =
                new List<OneCall24_Error_Log__c>();

            OneCall24_Error_Log__c logRecord =
                new OneCall24_Error_Log__c();

            logRecord.API_Endpoint__c = endpoint;
            logRecord.Operation__c = 'POST /reset';
            logRecord.HTTP_Status_Code__c = statusCode;
            logRecord.Error_Type__c = 'API Failure';
            logRecord.Error_Message__c =
                'Reset API returned HTTP status ' + statusCode;
            logRecord.Response_Body__c = responseBody;
            logRecord.Occurred_At__c = System.now();
            logRecord.Retry_Status__c = 'Failed';

            logs.add(logRecord);

            Database.insert(logs, false);
        }

    } catch (Exception ex) {

        OneCall24_Error_Log__c logRecord =
            new OneCall24_Error_Log__c();

        logRecord.API_Endpoint__c = endpoint;
        logRecord.Operation__c = 'POST /reset';
        logRecord.Error_Type__c = 'Exception';
        logRecord.Error_Message__c =
            ex.getMessage() +
            ' | Line Number: ' + ex.getLineNumber();
        logRecord.Occurred_At__c = System.now();
        logRecord.Retry_Status__c = 'Failed';

        Database.insert(logRecord, false);

        System.debug('RESET EXCEPTION: ' + ex.getMessage());
    }
}   
}