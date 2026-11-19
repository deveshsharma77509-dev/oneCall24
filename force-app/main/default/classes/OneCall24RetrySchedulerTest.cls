@isTest
private class OneCall24RetrySchedulerTest {

    private static final String CRON_EXP = '0 0 3 * * ?';

    // ---------- Mocks ----------

    private class OneCall24HttpMock implements HttpCalloutMock {
        private Boolean shouldThrow;
        OneCall24HttpMock(Boolean shouldThrow) {
            this.shouldThrow = shouldThrow;
        }
        public HTTPResponse respond(HTTPRequest req) {
            if (shouldThrow) {
                throw new CalloutException('Simulated callout failure');
            }
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"results":[]}');
            res.setStatusCode(200);
            return res;
        }
    }

    // ---------- Helpers ----------

    // Custom metadata cannot be created in tests, so we read the org's Default record.
    private static Boolean retryEnabled() {
        OneCall24_Settings__mdt s = OneCall24_Settings__mdt.getInstance('Default');
        return s != null && s.Retry_Enabled__c;
    }

    private static Integer maxRetry() {
        OneCall24_Settings__mdt s = OneCall24_Settings__mdt.getInstance('Default');
        return (s == null || s.Max_Retry__c == null) ? 3 : s.Max_Retry__c.intValue();
    }

    private static OneCall24_Error_Log__c makeLog(
        String operation, String candidateRef, Integer retryCount, String status
    ) {
        OneCall24_Error_Log__c log = new OneCall24_Error_Log__c();
        log.Operation__c = operation;
        log.Candidate_Reference__c = candidateRef;
        log.Retry_Count__c = retryCount;
        log.Retry_Status__c = status;
        return log;
    }

    private static OneCall24_Error_Log__c reload(Id logId) {
        return [
            SELECT Id, Retry_Count__c, Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Id = :logId
        ];
    }

    private static void runScheduler(Boolean mockThrows) {
        Test.setMock(HttpCalloutMock.class, new OneCall24HttpMock(mockThrows));
        Test.startTest();
        new OneCall24RetryScheduler().execute(null);
        Test.stopTest();
    }

    // ---------- Tests ----------

    // No pending logs: returns early (or skips entirely when retry is disabled)
    @isTest
    static void testNoPendingLogs() {
        runScheduler(false);

        System.assertEquals(0, [SELECT COUNT() FROM OneCall24_Error_Log__c],
            'No logs should be created by the scheduler.');
    }

    // GET /results is retried
    @isTest
    static void testRetryResults() {
        OneCall24_Error_Log__c log = makeLog('GET /results', null, 0, 'Pending');
        insert log;

        runScheduler(false);

        OneCall24_Error_Log__c result = reload(log.Id);
        if (retryEnabled()) {
            System.assertEquals(1, result.Retry_Count__c, 'Retry count should be incremented.');
            System.assertNotEquals('Pending', result.Retry_Status__c, 'Status should move on from Pending.');
        } else {
            System.assertEquals('Pending', result.Retry_Status__c, 'Nothing should change when retry is disabled.');
            System.assertEquals(0, result.Retry_Count__c, 'Count should be unchanged when retry is disabled.');
        }
    }

    // POST /confirm is retried via the queueable; a blank candidate ref is skipped
    @isTest
    static void testRetryConfirm() {
        OneCall24_Error_Log__c withRef    = makeLog('POST /confirm', 'REF-001', 0, 'Retry Scheduled');
        OneCall24_Error_Log__c withoutRef = makeLog('POST /confirm', null, 0, 'Retry Scheduled');
        insert new List<OneCall24_Error_Log__c>{ withRef, withoutRef };

        runScheduler(false);

        if (retryEnabled()) {
            System.assertEquals(1, reload(withRef.Id).Retry_Count__c, 'Confirm log should be retried.');
            System.assertEquals(1, reload(withoutRef.Id).Retry_Count__c, 'Count is incremented even if the ref is blank.');
        } else {
            System.assertEquals(0, reload(withRef.Id).Retry_Count__c, 'No change when retry is disabled.');
        }
    }

    // POST /reset is retried
    @isTest
    static void testRetryReset() {
        OneCall24_Error_Log__c log = makeLog('POST /reset', null, 0, 'Pending');
        insert log;

        runScheduler(false);

        OneCall24_Error_Log__c result = reload(log.Id);
        if (retryEnabled()) {
            System.assertEquals(1, result.Retry_Count__c, 'Retry count should be incremented.');
        } else {
            System.assertEquals(0, result.Retry_Count__c, 'No change when retry is disabled.');
        }
    }

    // All three operations in the same run
    @isTest
    static void testRetryAllOperationsTogether() {
        List<OneCall24_Error_Log__c> logs = new List<OneCall24_Error_Log__c>{
            makeLog('GET /results', null, 0, 'Pending'),
            makeLog('POST /confirm', 'REF-010', 0, 'Pending'),
            makeLog('POST /reset', null, 0, 'Retry Scheduled')
        };
        insert logs;

        runScheduler(false);

        Integer expected = retryEnabled() ? 1 : 0;
        for (OneCall24_Error_Log__c l : [
            SELECT Retry_Count__c FROM OneCall24_Error_Log__c
        ]) {
            System.assertEquals(expected, l.Retry_Count__c.intValue(), 'Each log should be handled consistently.');
        }
    }

    // Logs that already reached max retries are marked Failed
    @isTest
    static void testMaxRetryReached() {
        OneCall24_Error_Log__c log = makeLog('GET /results', null, maxRetry(), 'Retry Scheduled');
        insert log;

        runScheduler(false);

        OneCall24_Error_Log__c result = reload(log.Id);
        if (retryEnabled()) {
            System.assertEquals('Failed', result.Retry_Status__c, 'Log at max retries should be Failed.');
            System.assertEquals(maxRetry(), result.Retry_Count__c.intValue(), 'Count should not be incremented.');
        } else {
            System.assertEquals('Retry Scheduled', result.Retry_Status__c, 'No change when retry is disabled.');
        }
    }

    // A null retry count is treated as 0
    @isTest
    static void testNullRetryCountTreatedAsZero() {
        OneCall24_Error_Log__c log = makeLog('GET /results', null, null, 'Pending');
        insert log;

        runScheduler(false);

        OneCall24_Error_Log__c result = reload(log.Id);
        if (retryEnabled()) {
            System.assertEquals(1, result.Retry_Count__c, 'Null count should become 1.');
        }
    }

    // An unrecognised operation is still counted but triggers no API call
    @isTest
    static void testUnknownOperation() {
        OneCall24_Error_Log__c log = makeLog('SOMETHING ELSE', null, 0, 'Pending');
        insert log;

        runScheduler(false);

        OneCall24_Error_Log__c result = reload(log.Id);
        if (retryEnabled()) {
            System.assertEquals(1, result.Retry_Count__c, 'Count should still be incremented.');
        }
    }

    // Logs that are not Pending / Retry Scheduled are ignored
    @isTest
    static void testIgnoresOtherStatuses() {
        OneCall24_Error_Log__c log = makeLog('GET /results', null, 0, 'Failed');
        insert log;

        runScheduler(false);

        OneCall24_Error_Log__c result = reload(log.Id);
        System.assertEquals('Failed', result.Retry_Status__c, 'Failed logs must not be touched.');
        System.assertEquals(0, result.Retry_Count__c, 'Failed logs must not be retried.');
    }

    // The callout fails: the scheduler must handle it and not throw
    @isTest
    static void testCalloutFailureIsHandled() {
        insert new List<OneCall24_Error_Log__c>{
            makeLog('GET /results', null, 0, 'Pending'),
            makeLog('POST /confirm', 'REF-020', 0, 'Pending'),
            makeLog('POST /reset', null, 0, 'Pending')
        };

        Boolean threw = false;
        Test.setMock(HttpCalloutMock.class, new OneCall24HttpMock(true));
        Test.startTest();
        try {
            new OneCall24RetryScheduler().execute(null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'Scheduler should catch and log callout failures.');
    }

    // The job can be scheduled and has the expected cron settings
    @isTest
    static void testScheduleJob() {
        Test.setMock(HttpCalloutMock.class, new OneCall24HttpMock(false));

        Test.startTest();
        String jobId = System.schedule(
            'OneCall24 Retry Scheduler Test', CRON_EXP, new OneCall24RetryScheduler()
        );
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id, CronExpression, NextFireTime FROM CronTrigger WHERE Id = :jobId
        ];
        System.assertEquals(CRON_EXP, ct.CronExpression, 'Cron expression should match.');
        System.assertNotEquals(null, ct.NextFireTime, 'Job should have a next fire time.');
    }
}