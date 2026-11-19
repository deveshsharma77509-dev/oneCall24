/**
 * @Class Name    : OneCall24RetryScheduler
 * @Author        : Devesh Sharma
 * @Purpose       : Schedules retry processing for failed
 *                  OneCall24 API operations.
 * @Description   : Manages retry execution for previously failed
 *                  integration operations based on their
 *                  retry status and scheduling configuration.
 */

public class OneCall24RetryScheduler
    implements Schedulable {
    public void execute(SchedulableContext context) {
        OneCall24_Settings__mdt settings = OneCall24_Settings__mdt.getInstance('Default');
        if (settings == null || !settings.Retry_Enabled__c) {
            System.debug(LoggingLevel.WARN,'OneCall24 Retry skipped: Retry is disabled.');
            return;
        }
        Integer maxRetry = settings.Max_Retry__c == null? 3 : settings.Max_Retry__c.intValue();
        List<OneCall24_Error_Log__c> logs = [SELECT Id, Candidate_Reference__c,Operation__c, Retry_Count__c
            FROM OneCall24_Error_Log__c WHERE Retry_Status__c IN ('Pending', 'Retry Scheduled')];

        if (logs.isEmpty()) {
            System.debug(LoggingLevel.INFO,'OneCall24 Retry: No pending error logs found.');
            return;
        }

        List<String> confirmRefs = new List<String>();
        Boolean retryResults = false;
        Boolean retryReset = false;

        List<OneCall24_Error_Log__c> updates = new List<OneCall24_Error_Log__c>();
        for (OneCall24_Error_Log__c log : logs) {
            Integer retryCount = log.Retry_Count__c == null? 0 : log.Retry_Count__c.intValue();
            if (retryCount >= maxRetry) { 
                log.Retry_Status__c = 'Failed';
                updates.add(log);
                continue;
            }

            log.Retry_Count__c = retryCount + 1;
            log.Retry_Status__c = 'Retrying';
            updates.add(log);

            if (log.Operation__c == 'GET /results') {
                retryResults = true;
            }
            else if (log.Operation__c == 'POST /confirm' && !String.isBlank(log.Candidate_Reference__c)) {
                confirmRefs.add(log.Candidate_Reference__c);
            }
            else if (log.Operation__c == 'POST /reset') {
                retryReset = true;
            }
        }
        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);
            for (Database.SaveResult result : results) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.ERROR,'Retry log update failed: ' +result.getErrors()[0].getMessage());
                }
            }
        }

        try {
            if (retryResults) {
                OneCall24ApiService.fetchResults();
            }
            if (!confirmRefs.isEmpty()) {
                System.enqueueJob(new ConfirmCandidatesJob(confirmRefs));
            }
            if (retryReset) {
                OneCall24ApiService.resetConfirmations();
            }
            System.debug(LoggingLevel.INFO,'OneCall24 Retry Summary | Logs: ' + logs.size() +' | Confirm Candidates: ' + confirmRefs.size() +
                ' | Results Retry: ' + retryResults +' | Reset Retry: ' + retryReset);

        } catch (CalloutException ex) {
            OneCall24ExceptionHandler.handleCalloutException(ex, 'Retry Scheduler', 'Retry API', confirmRefs);

        } catch (Exception ex) {
            OneCall24ExceptionHandler.handleException(ex, 'Retry Scheduler', 'Retry API', confirmRefs);
        }
    }
}