@isTest
private class ConfirmCandidatesJobTest {

    // ---------- Mock ----------

    private class ConfirmHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  exceptionType; // null, 'callout' or 'generic'

        ConfirmHttpMock(Integer statusCode, String exceptionType) {
            this.statusCode    = statusCode;
            this.exceptionType = exceptionType;
        }

        public HTTPResponse respond(HTTPRequest req) {
            if (exceptionType == 'callout') {
                throw new CalloutException('Simulated callout failure');
            }
            if (exceptionType == 'generic') {
                throw new System.TypeException('Simulated generic failure');
            }
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status":"' + statusCode + '"}');
            res.setStatusCode(statusCode);
            return res;
        }
    }

    // ---------- Helpers ----------

    private static Integer logCount() {
        return [SELECT COUNT() FROM OneCall24_Error_Log__c];
    }

    // Enqueue so the job runs in its own transaction at stopTest,
    // which avoids "uncommitted work pending" errors before callouts.
    private static void runJob(List<String> refs, HttpCalloutMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        System.enqueueJob(new ConfirmCandidatesJob(refs));
        Test.stopTest();
    }

    // ---------- Tests ----------

    @isTest
    static void testNullRefs_returnsEarly() {
        Integer before = logCount();

        runJob(null, new ConfirmHttpMock(200, null));

        System.assertEquals(before, logCount(), 'No logs should be created for null refs.');
    }

    @isTest
    static void testEmptyRefs_returnsEarly() {
        Integer before = logCount();

        runJob(new List<String>(), new ConfirmHttpMock(200, null));

        System.assertEquals(before, logCount(), 'No logs should be created for empty refs.');
    }

    @isTest
    static void testSuccess_noNewErrorLogs() {
        Integer before = logCount();

        runJob(new List<String>{ 'REF-001', 'REF-002' }, new ConfirmHttpMock(200, null));

        System.assertEquals(before, logCount(), 'A successful confirm should not create error logs.');
    }

    @isTest
    static void testSuccess_resolvesPreviousErrors() {
        OneCall24_Error_Log__c existing = new OneCall24_Error_Log__c();
        existing.Candidate_Reference__c = 'REF-100';
        existing.Operation__c = 'POST /confirm';
        existing.Retry_Status__c = 'Pending';
        existing.Retry_Count__c = 1;
        insert existing;

        runJob(new List<String>{ 'REF-100' }, new ConfirmHttpMock(200, null));

        // resolveErrorLogs may update or remove the log, so handle both outcomes
        List<OneCall24_Error_Log__c> after = [
            SELECT Id, Retry_Status__c FROM OneCall24_Error_Log__c WHERE Id = :existing.Id
        ];
        if (!after.isEmpty()) {
            System.assertNotEquals('Pending', after[0].Retry_Status__c,
                'The previous error should no longer be Pending after a successful confirm.');
        }
    }

    @isTest
    static void testApiFailure_retryableOrNot_createsLogPerRef() {
        List<String> refs = new List<String>{ 'REF-201', 'REF-202', 'REF-203' };
        Integer before = logCount();

        // 503 is commonly retryable; the log is created either way,
        // only its retry status differs depending on the org's metadata.
        runJob(refs, new ConfirmHttpMock(503, null));

        System.assertEquals(before + refs.size(), logCount(), 'One error log per candidate ref expected.');
    }

    @isTest
    static void testApiFailure_clientError_createsLogPerRef() {
        List<String> refs = new List<String>{ 'REF-301', 'REF-302' };
        Integer before = logCount();

        runJob(refs, new ConfirmHttpMock(400, null));

        System.assertEquals(before + refs.size(), logCount(), 'One error log per candidate ref expected.');
    }

    @isTest
    static void testApiFailure_redirectStatusIsTreatedAsFailure() {
        List<String> refs = new List<String>{ 'REF-401' };
        Integer before = logCount();

        runJob(refs, new ConfirmHttpMock(302, null));

        System.assertEquals(before + 1, logCount(), 'Statuses outside 2xx should be logged as failures.');
    }

    @isTest
    static void testCalloutException_isHandledAndLogged() {
        List<String> refs = new List<String>{ 'REF-501', 'REF-502' };
        Integer before = logCount();

        // If this throws out of the job, the test fails at stopTest.
        runJob(refs, new ConfirmHttpMock(200, 'callout'));

        // OneCall24ApiClient may handle the CalloutException itself, in which case
        // the job logs nothing. If it lets the exception through, the job logs one
        // entry per ref. Either outcome is valid; anything else is not.
        Integer after = logCount();
        System.assert(after == before || after == before + refs.size(),
            'Expected either no new logs (handled in the API client) or one log per ref (handled in the job). Actual new logs: '
            + (after - before));
    }

    @isTest
    static void testGenericException_isHandledAndLogged() {
        List<String> refs = new List<String>{ 'REF-601' };
        Integer before = logCount();

        runJob(refs, new ConfirmHttpMock(200, 'generic'));

        System.assertEquals(before + 1, logCount(),
            'A generic exception should be logged once per candidate ref.');
    }
}