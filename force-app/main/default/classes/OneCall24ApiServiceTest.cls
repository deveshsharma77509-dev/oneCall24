@IsTest
private class OneCall24ApiServiceTest {

    // ==========================================
    // HELPER: GET VALID PICKLIST VALUE
    // ==========================================
    private static String getPicklistValue(String fieldName) {

        Schema.SObjectField fieldToken =
            Screening_Result__c.SObjectType.getDescribe()
                .fields.getMap().get(fieldName);

        if (fieldToken == null) {
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldToken.getDescribe();

        if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
            return null;
        }

        for (Schema.PicklistEntry entry :
             fieldDescribe.getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


    // ==========================================
    // HELPER: CREATE VALID CANDIDATE DATA
    // ==========================================
    private static Map<String, Object> getCandidate(String ref) {

        return new Map<String, Object>{
            'ref' => ref,
            'salesforce_contact_id' => '003000000000001',
            'first_name' => 'John',
            'last_name' => 'Doe',
            'mobile' => '9876543210',
            'email' => 'john@test.com',
            'status' => getPicklistValue('Status__c'),
            'outcome' => getPicklistValue('Outcome__c'),
            'interested' => getPicklistValue('Interested__c'),
            'right_to_work' => getPicklistValue('Right_To_Work__c'),
            'visa_valid' => getPicklistValue('Visa_Valid__c'),
            'ai_comments' => 'Test candidate',
            'care_experience_months' => 24,
            'job_title' => 'Care Assistant',
            'shift_pattern' => 'Day',
            'shifts_per_week' => 5,
            'postcode' => 'AB12 3CD',
            'travel_distance' => '10 miles',
            'driving_licence' => 'yes',
            'car_access' => 'yes',
            'call_count' => 2,
            'last_call_at' => '2026-11-18T10:30:00Z',
            'updated_at' => '2026-11-18T11:30:00Z'
        };
    }


    // ==========================================
    // HTTP MOCK - SUCCESS RESPONSE
    // ==========================================
    private class ApiMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            if (request.getEndpoint().contains('/results')) {

                response.setStatusCode(200);

                Map<String, Object> candidate =
                    getCandidate('TEST-001');

                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'count' => 1,
                            'more' => false,
                            'records' => new List<Object>{ candidate }
                        }
                    )
                );

            } else if (request.getEndpoint().contains('/confirm')) {

                response.setStatusCode(200);
                response.setBody(
                    '{"message":"Candidates confirmed successfully"}'
                );

            } else if (request.getEndpoint().contains('/reset')) {

                response.setStatusCode(200);
                response.setBody(
                    '{"message":"Reset completed successfully"}'
                );

            } else {

                response.setStatusCode(500);
                response.setBody(
                    '{"message":"Unexpected endpoint"}'
                );
            }

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - EMPTY RESPONSE
    // ==========================================
    private class ApiMockEmpty implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            response.setBody(
                '{"count":0,"more":false,"records":[]}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - FAILURE RESPONSE
    // ==========================================
    private class ApiMockFailure implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody(
                '{"message":"API error"}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - INVALID REFERENCE
    // ==========================================
    private class InvalidReferenceMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            response.setBody(
                '{"count":1,"more":false,"records":[' +
                '{"first_name":"NoRef","last_name":"Candidate"}' +
                ']}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - DUPLICATE REFERENCES
    // ==========================================
    private class DuplicateReferenceMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            if (request.getEndpoint().contains('/results')) {

                response.setStatusCode(200);

                Map<String, Object> candidate1 =
                    getCandidate('DUP-001');

                Map<String, Object> candidate2 =
                    getCandidate('DUP-001');

                candidate2.put('first_name', 'Updated');

                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'count' => 2,
                            'more' => false,
                            'records' => new List<Object>{
                                candidate1,
                                candidate2
                            }
                        }
                    )
                );

            } else if (request.getEndpoint().contains('/confirm')) {

                response.setStatusCode(200);
                response.setBody('{"message":"Confirmed"}');

            } else {

                response.setStatusCode(500);
                response.setBody('{"message":"Unexpected endpoint"}');
            }

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - INVALID INTEGER/DATETIME
    // ==========================================
    private class InvalidDataMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();

            if (request.getEndpoint().contains('/results')) {

                response.setStatusCode(200);

                Map<String, Object> candidate =
                    getCandidate('INVALID-DATA-001');

                candidate.put('care_experience_months', 'INVALID');
                candidate.put('shifts_per_week', 'INVALID');
                candidate.put('call_count', 'INVALID');
                candidate.put('last_call_at', 'INVALID-DATETIME');
                candidate.put('updated_at', 'INVALID-DATETIME');

                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'count' => 1,
                            'more' => false,
                            'records' => new List<Object>{ candidate }
                        }
                    )
                );

            } else if (request.getEndpoint().contains('/confirm')) {

                response.setStatusCode(200);
                response.setBody('{"message":"Confirmed"}');

            } else {

                response.setStatusCode(500);
                response.setBody('{"message":"Unexpected endpoint"}');
            }

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - RESET SUCCESS
    // ==========================================
    private class ResetSuccessMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(
                '{"message":"Reset successful"}'
            );

            return response;
        }
    }


    // ==========================================
    // HTTP MOCK - RESET FAILURE
    // ==========================================
    private class ResetFailureMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody(
                '{"message":"Reset failed"}'
            );

            return response;
        }
    }


    // ==========================================
    // TEST 1: SUCCESSFUL FETCH AND UPSERT
    // ==========================================
    @IsTest
    static void testFetchResultsSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMock()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        List<Screening_Result__c> records = [
            SELECT Id,
                   External_Reference__c,
                   First_Name__c,
                   Last_Name__c,
                   Email__c,
                   Mobile__c,
                   Care_Experience_Months__c,
                   Shifts_Per_Week__c,
                   Call_Count__c,
                   AI_Comments__c,
                   Job_Title__c,
                   Shift_Pattern__c,
                   Postcode__c,
                   Travel_Distance__c,
                   Driving_Licence__c,
                   Car_Access__c,
                   Last_Call_At__c,
                   Updated_At__c
            FROM Screening_Result__c
            WHERE External_Reference__c = 'TEST-001'
        ];

        System.assertEquals(1, records.size());
        System.assertEquals('John', records[0].First_Name__c);
        System.assertEquals('Doe', records[0].Last_Name__c);
        System.assertEquals('john@test.com', records[0].Email__c);
        System.assertEquals('9876543210', records[0].Mobile__c);

        System.assertEquals(
            24,
            records[0].Care_Experience_Months__c
        );

        System.assertEquals(
            5,
            records[0].Shifts_Per_Week__c
        );

        System.assertEquals(
            2,
            records[0].Call_Count__c
        );

        System.assertEquals(
            'Test candidate',
            records[0].AI_Comments__c
        );

        System.assertEquals(
            'Care Assistant',
            records[0].Job_Title__c
        );

        System.assertEquals(
            'Day',
            records[0].Shift_Pattern__c
        );

        System.assertEquals(
            'AB12 3CD',
            records[0].Postcode__c
        );

        System.assertEquals(
            '10 miles',
            records[0].Travel_Distance__c
        );

        System.assertEquals(
            'yes',
            records[0].Driving_Licence__c.toLowerCase()
        );

        System.assertEquals(
            'yes',
            records[0].Car_Access__c.toLowerCase()
        );

        System.assertNotEquals(null, records[0].Last_Call_At__c);
        System.assertNotEquals(null, records[0].Updated_At__c);
    }


    // ==========================================
    // TEST 2: EMPTY API RESPONSE
    // ==========================================
    @IsTest
    static void testFetchResultsEmptyResponse() {

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMockEmpty()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Screening_Result__c
            ]
        );
    }


    // ==========================================
    // TEST 3: API FAILURE
    // ==========================================
    @IsTest
    static void testFetchResultsFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMockFailure()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Screening_Result__c
            ]
        );
    }


    // ==========================================
    // TEST 4: CANDIDATE WITHOUT REFERENCE
    // ==========================================
    @IsTest
    static void testInvalidReferenceSkipped() {

        Test.setMock(
            HttpCalloutMock.class,
            new InvalidReferenceMock()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Screening_Result__c
            ]
        );
    }


    // ==========================================
    // TEST 5: DUPLICATE REFERENCES
    // ==========================================
    @IsTest
    static void testDuplicateReferences() {

        Test.setMock(
            HttpCalloutMock.class,
            new DuplicateReferenceMock()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        List<Screening_Result__c> records = [
            SELECT Id,
                   External_Reference__c,
                   First_Name__c
            FROM Screening_Result__c
            WHERE External_Reference__c = 'DUP-001'
        ];

        System.assertEquals(1, records.size());

       System.assertEquals(
    'John',
    records[0].First_Name__c,
    'First candidate should be retained when duplicate references are received.'
);
    }


    // ==========================================
    // TEST 6: INVALID INTEGER AND DATETIME
    // ==========================================
    @IsTest
    static void testInvalidDataConversion() {

        Test.setMock(
            HttpCalloutMock.class,
            new InvalidDataMock()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        List<Screening_Result__c> records = [
            SELECT Id,
                   External_Reference__c,
                   Care_Experience_Months__c,
                   Shifts_Per_Week__c,
                   Call_Count__c,
                   Last_Call_At__c,
                   Updated_At__c
            FROM Screening_Result__c
            WHERE External_Reference__c = 'INVALID-DATA-001'
        ];

        if (!records.isEmpty()) {

            System.assertEquals(
                null,
                records[0].Care_Experience_Months__c
            );

            System.assertEquals(
                null,
                records[0].Shifts_Per_Week__c
            );

            System.assertEquals(
                null,
                records[0].Call_Count__c
            );

            System.assertEquals(
                null,
                records[0].Last_Call_At__c
            );

            System.assertEquals(
                null,
                records[0].Updated_At__c
            );
        }
    }


    // ==========================================
    // TEST 7: RESET CONFIRMATIONS SUCCESS
    // ==========================================
    @IsTest
    static void testResetConfirmationsSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new ResetSuccessMock()
        );

        Test.startTest();

        OneCall24ApiService.resetConfirmations();

        Test.stopTest();
    }


    // ==========================================
    // TEST 8: RESET CONFIRMATIONS FAILURE
    // ==========================================
    @IsTest
    static void testResetConfirmationsFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new ResetFailureMock()
        );

        Test.startTest();

        OneCall24ApiService.resetConfirmations();

        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM OneCall24_Error_Log__c
                WHERE Operation__c = 'POST /reset'
                AND Error_Type__c = 'API Failure'
            ]
        );
    }


    // ==========================================
    // TEST 9: VERIFY API FAILURE ERROR LOG
    // ==========================================
    @IsTest
    static void testApiFailureErrorLog() {

        Test.setMock(
            HttpCalloutMock.class,
            new ApiMockFailure()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = [
            SELECT Id,
                   Operation__c,
                   HTTP_Status_Code__c,
                   Error_Type__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Operation__c = 'GET /results'
        ];

        System.assertEquals(1, logs.size());
        System.assertEquals(500, logs[0].HTTP_Status_Code__c);
        System.assertEquals('API Failure', logs[0].Error_Type__c);
        System.assertEquals('Pending', logs[0].Retry_Status__c);
    }


    // ==========================================
    // TEST 10: VERIFY MISSING REFERENCE ERROR LOG
    // ==========================================
    @IsTest
    static void testMissingReferenceErrorLog() {

        Test.setMock(
            HttpCalloutMock.class,
            new InvalidReferenceMock()
        );

        Test.startTest();

        OneCall24ApiService.fetchResults();

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = [
            SELECT Id,
                   Operation__c,
                   Error_Type__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Operation__c = 'GET /results - Mapping'
        ];

        System.assertEquals(1, logs.size());
        System.assertEquals('Record Failure', logs[0].Error_Type__c);
        System.assertEquals('Failed', logs[0].Retry_Status__c);
    }
}