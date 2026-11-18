@IsTest
private class ConfirmCandidatesJobTest {

    // ==========================================
    // HTTP MOCK - SUCCESS
    // ==========================================
    private class ConfirmSuccessMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            System.assertEquals('POST', request.getMethod());
            System.assertEquals(
                'application/json',
                request.getHeader('Content-Type')
            );

            System.assert(
                request.getEndpoint().contains('/confirm'),
                'Confirm endpoint should be called.'
            );

            Map<String, Object> requestBody =
                (Map<String, Object>) JSON.deserializeUntyped(
                    request.getBody()
                );

            System.assert(
                requestBody.containsKey('refs'),
                'Request body should contain refs.'
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"message":"Candidates confirmed successfully"}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - UNKNOWN REFERENCE
    // ==========================================
    private class ConfirmUnknownMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"unknown":["CAND-002"]}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - API FAILURE
    // ==========================================
    private class ConfirmFailureMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody(
                '{"message":"Internal server error"}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - EMPTY RESPONSE BODY
    // ==========================================
    private class ConfirmExceptionMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('INVALID JSON');

            return response;
        }
    }


    // ==========================================
    // TEST 1: SUCCESSFUL CONFIRMATION
    // ==========================================
    @IsTest
    static void testConfirmCandidatesSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new ConfirmSuccessMock()
        );

        Test.startTest();

        System.enqueueJob(
            new ConfirmCandidatesJob(
                new List<String>{
                    'CAND-001',
                    'CAND-002'
                }
            )
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM OneCall24_Error_Log__c
                WHERE Candidate_Reference__c IN (
                    'CAND-001',
                    'CAND-002'
                )
            ],
            'No error logs should be created for successful confirmation.'
        );
    }


    // ==========================================
    // TEST 2: API FAILURE - HTTP 500
    // ==========================================
    @IsTest
    static void testConfirmCandidatesFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new ConfirmFailureMock()
        );

        Test.startTest();

        System.enqueueJob(
            new ConfirmCandidatesJob(
                new List<String>{
                    'CAND-001'
                }
            )
        );

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = [
            SELECT Id,
                   Candidate_Reference__c,
                   HTTP_Status_Code__c,
                   Error_Type__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c = 'CAND-001'
        ];

        System.assertEquals(
            1,
            logs.size(),
            'An error log should be created.'
        );

        System.assertEquals(500, logs[0].HTTP_Status_Code__c);
        System.assertEquals('API Failure', logs[0].Error_Type__c);
        System.assertEquals('Retry Scheduled', logs[0].Retry_Status__c);
    }


    // ==========================================
    // TEST 3: UNKNOWN CANDIDATE REFERENCE
    // ==========================================
    @IsTest
    static void testConfirmUnknownReference() {

        Test.setMock(
            HttpCalloutMock.class,
            new ConfirmUnknownMock()
        );

        Test.startTest();

        System.enqueueJob(
            new ConfirmCandidatesJob(
                new List<String>{
                    'CAND-001',
                    'CAND-002'
                }
            )
        );

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = [
            SELECT Id,
                   Candidate_Reference__c,
                   Error_Type__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c = 'CAND-002'
        ];

        System.assertEquals(
            1,
            logs.size(),
            'Unknown candidate should have an error log.'
        );

        System.assertEquals('Record Failure', logs[0].Error_Type__c);
        System.assertEquals('Failed', logs[0].Retry_Status__c);
    }


    // ==========================================
    // TEST 4: EMPTY CANDIDATE REFERENCES
    // ==========================================
    @IsTest
    static void testEmptyCandidateReferences() {

        Test.startTest();

        System.enqueueJob(
            new ConfirmCandidatesJob(
                new List<String>()
            )
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM OneCall24_Error_Log__c
            ],
            'No logs should be created for empty references.'
        );
    }


    // ==========================================
    // TEST 5: NULL CANDIDATE REFERENCES
    // ==========================================
    @IsTest
    static void testNullCandidateReferences() {

        Test.startTest();

        System.enqueueJob(
            new ConfirmCandidatesJob(null)
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM OneCall24_Error_Log__c
            ],
            'No logs should be created for null references.'
        );
    }


    // ==========================================
    // TEST 6: INVALID JSON RESPONSE / EXCEPTION
    // ==========================================
    @IsTest
    static void testConfirmException() {

        Test.setMock(
            HttpCalloutMock.class,
            new ConfirmExceptionMock()
        );

        Test.startTest();

        System.enqueueJob(
            new ConfirmCandidatesJob(
                new List<String>{
                    'CAND-001'
                }
            )
        );

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = [
            SELECT Id,
                   Candidate_Reference__c,
                   Error_Type__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c = 'CAND-001'
        ];

        System.assertEquals(
            1,
            logs.size(),
            'Exception should generate an error log.'
        );

        System.assertEquals('Exception', logs[0].Error_Type__c);
        System.assertEquals('Retry Scheduled', logs[0].Retry_Status__c);
    }
}