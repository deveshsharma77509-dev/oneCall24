@isTest
private class OneCall24ApiServiceTest {

    // ---------- Mock ----------

    private class ApiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  body;
        private String  exceptionType; // null, 'callout' or 'generic'

        ApiMock(Integer statusCode, String body, String exceptionType) {
            this.statusCode    = statusCode;
            this.body          = body;
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
            res.setBody(body);
            res.setStatusCode(statusCode);
            return res;
        }
    }

    // ---------- Helpers ----------

    private static Integer logCount() {
        return [SELECT COUNT() FROM OneCall24_Error_Log__c];
    }

    private static Integer resultCount() {
        return [SELECT COUNT() FROM Screening_Result__c];
    }

    private static Map<String, Object> candidate(String ref) {
        return new Map<String, Object>{
            'ref'                    => ref,
            'first_name'             => 'Test',
            'last_name'              => 'Candidate ' + ref,
            'mobile'                 => '07000000000',
            'email'                  => ref.toLowerCase() + '@example.com',
            'status'                 => 'Completed',
            'outcome'                => 'Pass',
            'care_experience_months' => 12,
            'shifts_per_week'        => 3,
            'last_call_at'           => '2026-11-01T10:00:00Z',
            'updated_at'             => '2026-11-02T10:00:00Z'
        };
    }

    private static String recordsBody(List<Object> records) {
        return JSON.serialize(new Map<String, Object>{ 'records' => records });
    }

    private static void runFetch(ApiMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        OneCall24ApiService.fetchResults();
        Test.stopTest();
    }

    private static void runReset(ApiMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        OneCall24ApiService.resetConfirmations();
        Test.stopTest();
    }

    // =====================================================
    // fetchResults
    // =====================================================

    @isTest
    static void testFetchResults_success_upsertsRecords() {
        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(200,
            recordsBody(new List<Object>{ candidate('REF-001'), candidate('REF-002') }), null));

        System.assertEquals(resultsBefore + 2, resultCount(), 'Both candidates should be upserted.');
        System.assertEquals(logsBefore, logCount(), 'No error logs expected on success.');
    }

    @isTest
    static void testFetchResults_upsertTwiceDoesNotDuplicate() {
        Test.setMock(HttpCalloutMock.class,
            new ApiMock(200, recordsBody(new List<Object>{ candidate('REF-010') }), null));

        Test.startTest();
        OneCall24ApiService.fetchResults();
        OneCall24ApiService.fetchResults();
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Screening_Result__c WHERE External_Reference__c = 'REF-010'],
            'Upsert on External_Reference__c should not create duplicates.');
    }

    @isTest
    static void testFetchResults_duplicateRefsInResponse_processedOnce() {
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(200,
            recordsBody(new List<Object>{ candidate('REF-020'), candidate('REF-020') }), null));

        System.assertEquals(resultsBefore + 1, resultCount(), 'Duplicate refs should be processed once.');
    }

    @isTest
    static void testFetchResults_missingRef_logsRecordFailure() {
        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        Map<String, Object> noRef = candidate('X');
        noRef.remove('ref');

        runFetch(new ApiMock(200, recordsBody(new List<Object>{ noRef }), null));

        System.assertEquals(logsBefore + 1, logCount(), 'A missing ref should create one error log.');
        System.assertEquals(resultsBefore, resultCount(), 'No record should be upserted without a ref.');
    }

    @isTest
    static void testFetchResults_mixOfValidAndMissingRef() {
        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        Map<String, Object> noRef = candidate('X');
        noRef.remove('ref');

        runFetch(new ApiMock(200,
            recordsBody(new List<Object>{ candidate('REF-030'), noRef }), null));

        System.assertEquals(resultsBefore + 1, resultCount(), 'The valid candidate should be upserted.');
        System.assertEquals(logsBefore + 1, logCount(), 'The invalid candidate should be logged.');
    }

    @isTest
    static void testFetchResults_badFieldValue_savedOrLogged() {
        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        Map<String, Object> bad = candidate('REF-040');
        bad.put('care_experience_months', 'not-a-number');
        bad.put('last_call_at', 'not-a-date');

        runFetch(new ApiMock(200, recordsBody(new List<Object>{ bad }), null));

        // Depending on how OneCall24Helper parses values, the record is either
        // saved with blanks or logged as a mapping failure. It must not vanish.
        Integer handled = (resultCount() - resultsBefore) + (logCount() - logsBefore);
        System.assert(handled >= 1, 'The candidate must be either saved or logged.');
    }

    @isTest
    static void testFetchResults_upsertFailure_logsDmlError() {
        Integer logsBefore = logCount();

        // Value far longer than any standard text field allows, so the upsert
        // fails for this row (partial success is enabled in the service).
        Map<String, Object> tooLong = candidate('REF-050');
        tooLong.put('first_name', 'A'.repeat(600));

        runFetch(new ApiMock(200, recordsBody(new List<Object>{ tooLong }), null));

        System.assert(logCount() > logsBefore, 'A failed upsert should create an error log.');
    }

    @isTest
    static void testFetchResults_emptyRecords_doesNothing() {
        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(200, recordsBody(new List<Object>()), null));

        System.assertEquals(resultsBefore, resultCount(), 'Nothing should be upserted.');
        System.assertEquals(logsBefore, logCount(), 'No logs expected.');
    }

    @isTest
    static void testFetchResults_noRecordsKey_doesNothing() {
        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(200, '{}', null));

        System.assertEquals(resultsBefore, resultCount(), 'Nothing should be upserted.');
        System.assertEquals(logsBefore, logCount(), 'No logs expected.');
    }

    @isTest
    static void testFetchResults_apiFailure_logsOnce() {
        Integer logsBefore = logCount();

        runFetch(new ApiMock(500, '{"error":"server error"}', null));

        System.assertEquals(logsBefore + 1, logCount(), 'A non-2xx response should create one error log.');
    }

    @isTest
    static void testFetchResults_clientError_logsOnce() {
        Integer logsBefore = logCount();

        runFetch(new ApiMock(401, '{"error":"unauthorized"}', null));

        System.assertEquals(logsBefore + 1, logCount(), 'A non-2xx response should create one error log.');
    }

    @isTest
    static void testFetchResults_invalidJson_isHandledAndLogged() {
        Integer logsBefore = logCount();

        runFetch(new ApiMock(200, 'this is not json', null));

        System.assertEquals(logsBefore + 1, logCount(), 'A JSON parse failure should be logged once.');
    }

    @isTest
    static void testFetchResults_calloutException_isHandled() {
        Integer logsBefore = logCount();

        runFetch(new ApiMock(200, '{}', 'callout'));

        // OneCall24ApiClient may handle the CalloutException itself; either outcome is valid.
        Integer after = logCount();
        System.assert(after == logsBefore || after == logsBefore + 1,
            'Expected at most one new log. Actual new logs: ' + (after - logsBefore));
    }

    @isTest
    static void testFetchResults_genericException_isHandledAndLogged() {
        Integer logsBefore = logCount();

        runFetch(new ApiMock(200, '{}', 'generic'));

        System.assertEquals(logsBefore + 1, logCount(), 'A generic exception should be logged once.');
    }

    // =====================================================
    // resetConfirmations
    // =====================================================

    @isTest
    static void testReset_success_noLogs() {
        Integer logsBefore = logCount();

        runReset(new ApiMock(200, '{"status":"ok"}', null));

        System.assertEquals(logsBefore, logCount(), 'No error logs expected on success.');
    }

    @isTest
    static void testReset_apiFailure_logsOnce() {
        Integer logsBefore = logCount();

        runReset(new ApiMock(500, '{"error":"server error"}', null));

        System.assertEquals(logsBefore + 1, logCount(), 'A non-2xx response should create one error log.');
    }

    @isTest
    static void testReset_clientError_logsOnce() {
        Integer logsBefore = logCount();

        runReset(new ApiMock(400, '{"error":"bad request"}', null));

        System.assertEquals(logsBefore + 1, logCount(), 'A non-2xx response should create one error log.');
    }

    @isTest
    static void testReset_calloutException_isHandled() {
        Integer logsBefore = logCount();

        runReset(new ApiMock(200, '{}', 'callout'));

        Integer after = logCount();
        System.assert(after == logsBefore || after == logsBefore + 1,
            'Expected at most one new log. Actual new logs: ' + (after - logsBefore));
    }

    @isTest
    static void testReset_genericException_isHandledAndLogged() {
        Integer logsBefore = logCount();

        runReset(new ApiMock(200, '{}', 'generic'));

        System.assertEquals(logsBefore + 1, logCount(), 'A generic exception should be logged once.');
    }
}