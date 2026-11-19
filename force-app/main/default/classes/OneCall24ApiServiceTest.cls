@IsTest
private class OneCall24ApiServiceTest {

    // ---------- Mock ----------

    private class ApiMock implements HttpCalloutMock {

        private Integer statusCode;
        private String body;
        private String exceptionType;

        ApiMock(Integer statusCode, String body, String exceptionType) {
            this.statusCode = statusCode;
            this.body = body;
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

    // Get active picklist value
    private static String getActivePicklistValue(
        String fieldName,
        String preferredValue
    ) {

        Schema.SObjectField fieldToken =
            Screening_Result__c.SObjectType.getDescribe()
            .fields.getMap().get(fieldName);

        if (fieldToken == null) {
            return preferredValue;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldToken.getDescribe();

        if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
            return preferredValue;
        }

        for (Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()) {

            if (entry.isActive() &&
                entry.getValue() == preferredValue) {
                return preferredValue;
            }
        }

        for (Schema.PicklistEntry entry :
            fieldDescribe.getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }

    // Create candidate test data
    private static Map<String, Object> candidate(String ref) {

        return new Map<String, Object>{
            'ref' => ref,
            'first_name' => 'Test',
            'last_name' => 'Candidate ' + ref,
            'mobile' => '07000000000',
            'email' => ref.toLowerCase() + '@example.com',

            'status' => getActivePicklistValue('Status__c', 'Completed'),
            'outcome' => getActivePicklistValue('Outcome__c', 'Pass'),

            'care_experience_months' => 12,
            'job_title' => 'Care Assistant',
            'shifts_per_week' => 3,
            'postcode' => 'SW1A 1AA',
            'travel_distance' => '10 miles',
            'call_count' => 2,
            'last_call_at' => '2026-11-01T10:00:00Z',
            'updated_at' => '2026-11-02T10:00:00Z'
        };
    }

    private static String recordsBody(List<Object> records) {
        return JSON.serialize(
            new Map<String, Object>{'records' => records}
        );
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
    // FETCH RESULTS
    // =====================================================

    @IsTest
    static void testFetchResults_success_upsertsRecords() {

        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>{
                candidate('REF-001'),
                candidate('REF-002')
            }),
            null
        ));

        System.assertEquals(
            resultsBefore + 2,
            resultCount(),
            'Both candidates should be upserted.'
        );

        System.assertEquals(
            logsBefore,
            logCount(),
            'No error logs expected on success.'
        );
    }

    @IsTest
    static void testFetchResults_upsertTwiceDoesNotDuplicate() {

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMock(
                200,
                recordsBody(new List<Object>{candidate('REF-010')}),
                null
            )
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();
        OneCall24ApiService.fetchResults();

        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Screening_Result__c
                WHERE External_Reference__c = 'REF-010'
            ],
            'Upsert should not create duplicates.'
        );
    }

    @IsTest
    static void testFetchResults_duplicateRefsInResponse_processedOnce() {

        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>{
                candidate('REF-020'),
                candidate('REF-020')
            }),
            null
        ));

        System.assertEquals(
            resultsBefore + 1,
            resultCount(),
            'Duplicate refs should be processed once.'
        );
    }

    @IsTest
    static void testFetchResults_missingRef_logsRecordFailure() {

        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        Map<String, Object> noRef = candidate('X');
        noRef.remove('ref');

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>{noRef}),
            null
        ));

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'Missing ref should create one error log.'
        );

        System.assertEquals(
            resultsBefore,
            resultCount(),
            'No record should be upserted without a ref.'
        );
    }

    @IsTest
    static void testFetchResults_mixOfValidAndMissingRef() {

        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        Map<String, Object> noRef = candidate('X');
        noRef.remove('ref');

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>{
                candidate('REF-030'),
                noRef
            }),
            null
        ));

        System.assertEquals(
            resultsBefore + 1,
            resultCount(),
            'Valid candidate should be upserted.'
        );

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'Invalid candidate should be logged.'
        );
    }

    @IsTest
    static void testFetchResults_badFieldValue_savedOrLogged() {

        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        Map<String, Object> bad = candidate('REF-040');

        bad.put('care_experience_months', 'not-a-number');
        bad.put('last_call_at', 'not-a-date');

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>{bad}),
            null
        ));

        Integer handled =
            (resultCount() - resultsBefore) +
            (logCount() - logsBefore);

        System.assert(
            handled >= 1,
            'Candidate must be either saved or logged.'
        );
    }

    @IsTest
    static void testFetchResults_upsertFailure_logsDmlError() {

        Integer logsBefore = logCount();

        Map<String, Object> tooLong = candidate('REF-050');
        tooLong.put('first_name', 'A'.repeat(600));

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>{tooLong}),
            null
        ));

        System.assert(
            logCount() > logsBefore,
            'Failed upsert should create an error log.'
        );
    }

    @IsTest
    static void testFetchResults_emptyRecords_doesNothing() {

        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(
            200,
            recordsBody(new List<Object>()),
            null
        ));

        System.assertEquals(resultsBefore, resultCount());
        System.assertEquals(logsBefore, logCount());
    }

    @IsTest
    static void testFetchResults_noRecordsKey_doesNothing() {

        Integer logsBefore = logCount();
        Integer resultsBefore = resultCount();

        runFetch(new ApiMock(200, '{}', null));

        System.assertEquals(resultsBefore, resultCount());
        System.assertEquals(logsBefore, logCount());
    }

    @IsTest
    static void testFetchResults_apiFailure_logsOnce() {

        Integer logsBefore = logCount();

        runFetch(new ApiMock(
            500,
            '{"error":"server error"}',
            null
        ));

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'API failure should create one error log.'
        );
    }

    @IsTest
    static void testFetchResults_invalidJson_isHandledAndLogged() {

        Integer logsBefore = logCount();

        runFetch(new ApiMock(
            200,
            'this is not json',
            null
        ));

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'JSON parsing failure should be logged.'
        );
    }

    @IsTest
    static void testFetchResults_calloutException_isHandled() {

        Integer logsBefore = logCount();

        runFetch(new ApiMock(200, '{}', 'callout'));

        Integer after = logCount();

        System.assert(
            after == logsBefore || after == logsBefore + 1,
            'Expected at most one new log.'
        );
    }

    @IsTest
    static void testFetchResults_genericException_isHandledAndLogged() {

        Integer logsBefore = logCount();

        runFetch(new ApiMock(200, '{}', 'generic'));

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'Generic exception should be logged.'
        );
    }

    // =====================================================
    // RESET CONFIRMATIONS
    // =====================================================

    @IsTest
    static void testReset_success_noLogs() {

        Integer logsBefore = logCount();

        runReset(new ApiMock(
            200,
            '{"status":"ok"}',
            null
        ));

        System.assertEquals(
            logsBefore,
            logCount(),
            'No error logs expected on success.'
        );
    }

    @IsTest
    static void testReset_apiFailure_logsOnce() {

        Integer logsBefore = logCount();

        runReset(new ApiMock(
            500,
            '{"error":"server error"}',
            null
        ));

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'Reset API failure should create one error log.'
        );
    }

    @IsTest
    static void testReset_calloutException_isHandled() {

        Integer logsBefore = logCount();

        runReset(new ApiMock(200, '{}', 'callout'));

        Integer after = logCount();

        System.assert(
            after == logsBefore || after == logsBefore + 1,
            'Expected at most one new log.'
        );
    }

    @IsTest
    static void testReset_genericException_isHandledAndLogged() {

        Integer logsBefore = logCount();

        runReset(new ApiMock(200, '{}', 'generic'));

        System.assertEquals(
            logsBefore + 1,
            logCount(),
            'Generic exception should be logged.'
        );
    }
}