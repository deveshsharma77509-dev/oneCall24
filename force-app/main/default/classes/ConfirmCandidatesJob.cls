/**
 * @Class Name    : ConfirmCandidatesJob
 * @Author        : Devesh Sharma
 * @Purpose       : Handles asynchronous candidate confirmation
 *                  processing through Salesforce.
 * @Description   : Processes candidate confirmation requests
 *                  and communicates with the OneCall24 API
 *                  to confirm selected candidates.
 */

public class ConfirmCandidatesJob implements Queueable, Database.AllowsCallouts {
    
    private List<String> candidateRefs;
    public ConfirmCandidatesJob(List<String> refs) {this.candidateRefs = refs;}
    
    public void execute(QueueableContext context) {
        
        if (candidateRefs == null || candidateRefs.isEmpty()) {
            return;
        }
        try {
            // 1. Call Confirm API
            HttpResponse response = OneCall24ApiClient.confirmCandidates(candidateRefs);
            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();
            System.debug('CONFIRM STATUS: ' + statusCode);
            System.debug('CONFIRM RESPONSE: ' + responseBody);
            
            // 2. Handle API Failure
            if (statusCode < 200 || statusCode >= 300) {
                Boolean retryable = OneCall24ExceptionHandler.isRetryableStatusCode(statusCode);
                List<OneCall24_Error_Log__c> errorLogs = new List<OneCall24_Error_Log__c>();
                
                for (String ref : candidateRefs) 
                {
                    errorLogs.add(OneCall24Helper.createErrorLog(ref,'/confirm','POST /confirm',statusCode,
                                                                 'API Failure','Confirm API returned HTTP status ' +statusCode,
                                                                 responseBody,retryable ? 'Pending' : 'Not Required'));
                }
                OneCall24Helper.saveErrorLogs(errorLogs);
                return;
            }
            
            // 3. Resolve Previous Confirmation Errors
            OneCall24Helper.resolveErrorLogs(candidateRefs);
            System.debug('CONFIRM SUCCESS COUNT: ' + candidateRefs.size());
        }
        catch (CalloutException ex) {
            OneCall24ExceptionHandler.handleCalloutException(ex,'POST /confirm','/confirm',candidateRefs);
        } catch (Exception ex) {
            OneCall24ExceptionHandler.handleException(ex,'POST /confirm','/confirm',candidateRefs);
        }
    }
}