@IsTest
private class OneCall24ApiClientTest {
    // Mock HTTP Response
    private class OneCall24Mock implements HttpCalloutMock {

        private Integer statusCode;
        private String responseBody;
        public OneCall24Mock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        public HTTPResponse respond(HTTPRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            return response;
        }
    }

    // Test GET Results API
    @IsTest
    static void testGetResults() {
        Test.setMock(HttpCalloutMock.class,new OneCall24Mock(200, '{"success":true,"results":[]} '));
        Test.startTest();
        HttpResponse response = OneCall24ApiClient.getResults();
        Test.stopTest();
        System.assertEquals(200, response.getStatusCode());
        System.assert(response.getBody().contains('success'));
    }

    // Test POST Confirm Candidates API
    @IsTest
    static void testConfirmCandidates() {
        List<String> candidateRefs = new List<String>{
            'CAND001',
            'CAND002'
        };
        Test.setMock(HttpCalloutMock.class,new OneCall24Mock(200,'{"success":true}'));
        Test.startTest();
        HttpResponse response = OneCall24ApiClient.confirmCandidates(candidateRefs);
        Test.stopTest();
        System.assertEquals(200,response.getStatusCode());
        System.assert(response.getBody().contains('success'));
    }

    // Test POST Confirm with Empty List
    @IsTest
    static void testConfirmCandidatesEmptyList() {
        Test.startTest();
        try {
            OneCall24ApiClient.confirmCandidates(new List<String>());
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals('Candidate references cannot be empty.',e.getMessage());
        }
        Test.stopTest();
    }

    // Test POST Confirm with Null List
    @IsTest
    static void testConfirmCandidatesNull() {
        Test.startTest();
        try {
            OneCall24ApiClient.confirmCandidates(null);
            System.assert(false, 'Expected IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals('Candidate references cannot be empty.', e.getMessage());
        }
        Test.stopTest();
    }

    // Test POST Reset API
    @IsTest
    static void testResetConfirmations() {
        Test.setMock(HttpCalloutMock.class, new OneCall24Mock(200, '{"success":true}'));
        Test.startTest();
        HttpResponse response = OneCall24ApiClient.resetConfirmations();
        Test.stopTest();
        System.assertEquals(200, response.getStatusCode());
    }

    // Test API Error Response
    @IsTest
    static void testErrorResponse() {
        Test.setMock(HttpCalloutMock.class,new OneCall24Mock(500, '{"error":"Internal Server Error"}'));
        Test.startTest();
        HttpResponse response = OneCall24ApiClient.getResults();
        Test.stopTest();
        System.assertEquals(500, response.getStatusCode());
        System.assert(response.getBody().contains('error'));
    }
}