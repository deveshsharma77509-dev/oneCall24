global class OneCall24RetryScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        List<OneCall24_Error_Log__c> errorLogs = [
            SELECT Id,
                   Candidate_Reference__c,
                   HTTP_Status_Code__c,
                   Error_Type__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Retry_Status__c = 'Pending'
            AND (
                HTTP_Status_Code__c = 500
                OR Error_Type__c IN (
                    'API Failure',
                    'Record Failure',
                    'Exception'
                )
            )
            AND Candidate_Reference__c != null
        ];

        if (errorLogs.isEmpty()) {
            System.debug('No eligible retry records found.');
            return;
        }

        Set<String> candidateRefs = new Set<String>();

        for (OneCall24_Error_Log__c log : errorLogs) {
            candidateRefs.add(log.Candidate_Reference__c);
            log.Retry_Status__c = 'Retry Scheduled';
        }

        update errorLogs;

        System.enqueueJob(
            new ConfirmCandidatesJob(
                new List<String>(candidateRefs)
            )
        );

        System.debug(
            'Retry candidates submitted: ' + candidateRefs.size()
        );
    }
}