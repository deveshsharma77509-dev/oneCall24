@isTest
private class OneCall24RetrySchedulerTest {

    private static final String CRON_EXP = '0 0 3 * * ?';

    // Generic mock so the enqueued ConfirmCandidatesJob can run its callout in Test.stopTest()
    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    private static OneCall24_Error_Log__c buildLog(
        String candidateRef,
        Decimal httpStatus,
        String errorType,
        String retryStatus
    ) {
        return new OneCall24_Error_Log__c(
            Candidate_Reference__c = candidateRef,
            HTTP_Status_Code__c    = httpStatus,
            Error_Type__c          = errorType,
            Retry_Status__c        = retryStatus
        );
    }

    private static Map<Id, OneCall24_Error_Log__c> reload(List<OneCall24_Error_Log__c> logs) {
        return new Map<Id, OneCall24_Error_Log__c>([
            SELECT Id, Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Id IN :logs
        ]);
    }

    // ---------- Tests ----------

    @isTest
    static void testNoEligibleRecords_EarlyReturn() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        new OneCall24RetryScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM OneCall24_Error_Log__c],
            'No records should exist or be created');
    }

    @isTest
    static void testEligibleBy_Http500() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        OneCall24_Error_Log__c log = buildLog('CAND-500', 500, null, 'Pending');
        insert log;

        Test.startTest();
        new OneCall24RetryScheduler().execute(null);
        Test.stopTest();

        System.assertNotEquals('Pending',
            reload(new List<OneCall24_Error_Log__c>{ log }).get(log.Id).Retry_Status__c,
            'Log with HTTP 500 should have been picked up for retry');
    }

    @isTest
    static void testEligibleBy_ErrorTypes() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        List<OneCall24_Error_Log__c> logs = new List<OneCall24_Error_Log__c>{
            buildLog('CAND-API', 400, 'API Failure',    'Pending'),
            buildLog('CAND-REC', 400, 'Record Failure', 'Pending'),
            buildLog('CAND-EXC', 400, 'Exception',      'Pending')
        };
        insert logs;

        Test.startTest();
        new OneCall24RetryScheduler().execute(null);
        Test.stopTest();

        Map<Id, OneCall24_Error_Log__c> after = reload(logs);
        for (OneCall24_Error_Log__c l : logs) {
            System.assertNotEquals('Pending', after.get(l.Id).Retry_Status__c,
                'Eligible error type should have been picked up');
        }
    }

    @isTest
    static void testIneligibleRecords_AreNotTouched() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        OneCall24_Error_Log__c notPending  = buildLog('CAND-1', 500, 'API Failure', 'Retry Scheduled');
        OneCall24_Error_Log__c noCandidate = buildLog(null,     500, 'API Failure', 'Pending');
        OneCall24_Error_Log__c wrongType   = buildLog('CAND-3', 404, null,          'Pending');
        List<OneCall24_Error_Log__c> logs = new List<OneCall24_Error_Log__c>{ notPending, noCandidate, wrongType };
        insert logs;

        Test.startTest();
        new OneCall24RetryScheduler().execute(null);
        Test.stopTest();

        Map<Id, OneCall24_Error_Log__c> after = reload(logs);
        System.assertEquals('Retry Scheduled', after.get(notPending.Id).Retry_Status__c,  'Non-pending log must not change');
        System.assertEquals('Pending',         after.get(noCandidate.Id).Retry_Status__c, 'Log without candidate ref must not change');
        System.assertEquals('Pending',         after.get(wrongType.Id).Retry_Status__c,   'Non-matching log must not change');
    }

    @isTest
    static void testDuplicateCandidateRefs_Bulk() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        List<OneCall24_Error_Log__c> logs = new List<OneCall24_Error_Log__c>();
        for (Integer i = 0; i < 20; i++) {
            // 10 distinct refs, each appearing twice
            logs.add(buildLog('CAND-' + Math.mod(i, 10), 500, 'API Failure', 'Pending'));
        }
        insert logs;

        Test.startTest();
        new OneCall24RetryScheduler().execute(null);
        Test.stopTest();

        Map<Id, OneCall24_Error_Log__c> after = reload(logs);
        for (OneCall24_Error_Log__c l : logs) {
            System.assertNotEquals('Pending', after.get(l.Id).Retry_Status__c,
                'All eligible logs should be moved out of Pending');
        }
    }

    @isTest
    static void testScheduleViaSystemSchedule() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        insert buildLog('CAND-SCHED', 500, 'Exception', 'Pending');

        Test.startTest();
        String jobId = System.schedule('OneCall24 Retry Test Job', CRON_EXP, new OneCall24RetryScheduler());
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression, NextFireTime FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(CRON_EXP, ct.CronExpression, 'Cron expression should match');
        System.assertNotEquals(null, ct.NextFireTime, 'Job should be scheduled for a future run');
    }
}