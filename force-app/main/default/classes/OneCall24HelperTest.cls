@IsTest
private class OneCall24HelperTest {

    // Get valid Error Type picklist value
    private static String getValidErrorType() {

        List<Schema.PicklistEntry> values =
            OneCall24_Error_Log__c.Error_Type__c
            .getDescribe()
            .getPicklistValues();

        for (Schema.PicklistEntry entry : values) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        System.assert(
            false,
            'No active Error Type picklist values found.'
        );

        return null;
    }

    // Test getString()
    @IsTest
    static void testGetString() {

        Map<String, Object> data = new Map<String, Object>{
            'name' => 'ABC',
            'number' => 123,
            'emptyValue' => null
        };

        System.assertEquals(
            'ABC',
            OneCall24Helper.getString(data, 'name')
        );

        System.assertEquals(
            '123',
            OneCall24Helper.getString(data, 'number')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getString(data, 'emptyValue')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getString(data, 'unknown')
        );
    }

    // Test getDecimal()
    @IsTest
    static void testGetDecimal() {

        Map<String, Object> data = new Map<String, Object>{
            'amount' => 1500.50,
            'nullValue' => null,
            'emptyValue' => ''
        };

        System.assertEquals(
            Decimal.valueOf('1500.50'),
            OneCall24Helper.getDecimal(data, 'amount')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getDecimal(data, 'nullValue')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getDecimal(data, 'emptyValue')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getDecimal(data, 'unknown')
        );
    }

    // Test getDateTime()
    @IsTest
    static void testGetDateTime() {

        Map<String, Object> data = new Map<String, Object>{
            'createdDate' => '2026-11-19T10:30:00.000Z',
            'nullDate' => null,
            'emptyDate' => ''
        };

        Datetime result = OneCall24Helper.getDateTime(
            data,
            'createdDate'
        );

        System.assertNotEquals(null, result);

        System.assertEquals(
            Datetime.newInstanceGmt(2026, 11, 19, 10, 30, 0),
            result
        );

        System.assertEquals(
            null,
            OneCall24Helper.getDateTime(data, 'nullDate')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getDateTime(data, 'emptyDate')
        );

        System.assertEquals(
            null,
            OneCall24Helper.getDateTime(data, 'unknown')
        );
    }

    // Test createErrorLog()
    @IsTest
    static void testCreateErrorLog() {

        String errorType = getValidErrorType();

        OneCall24_Error_Log__c errorLog =
            OneCall24Helper.createErrorLog(
                'TEST001',
                '/api/candidates',
                'GET',
                500,
                errorType,
                'Internal Server Error',
                '{"error":"Something went wrong"}',
                'Pending'
            );

        System.assertEquals(
            'TEST001',
            errorLog.Candidate_Reference__c
        );

        System.assertEquals(
            '/api/candidates',
            errorLog.API_Endpoint__c
        );

        System.assertEquals(
            'GET',
            errorLog.Operation__c
        );

        System.assertEquals(
            500,
            errorLog.HTTP_Status_Code__c
        );

        System.assertEquals(
            errorType,
            errorLog.Error_Type__c
        );

        System.assertEquals(
            'Internal Server Error',
            errorLog.Error_Message__c
        );

        System.assertEquals(
            'Pending',
            errorLog.Retry_Status__c
        );

        System.assertNotEquals(
            null,
            errorLog.Occurred_At__c
        );
    }

    // Test text truncation
    @IsTest
    static void testTextTruncation() {

        String longText = '';

        for (Integer i = 0; i < 400; i++) {
            longText += 'A';
        }

        OneCall24_Error_Log__c errorLog =
            OneCall24Helper.createErrorLog(
                longText,
                longText,
                longText,
                500,
                getValidErrorType(),
                longText,
                longText,
                'Pending'
            );

        System.assertEquals(
            100,
            errorLog.Candidate_Reference__c.length()
        );

        System.assertEquals(
            255,
            errorLog.API_Endpoint__c.length()
        );

        System.assertEquals(
            100,
            errorLog.Operation__c.length()
        );

        System.assertEquals(
            400,
            errorLog.Error_Message__c.length()
        );

        System.assertEquals(
            400,
            errorLog.Response_Body__c.length()
        );
    }

    // Test saveErrorLogs()
    @IsTest
    static void testSaveErrorLogs() {

        String errorType = getValidErrorType();

        List<OneCall24_Error_Log__c> logs =
            new List<OneCall24_Error_Log__c>();

        logs.add(
            OneCall24Helper.createErrorLog(
                'TEST001',
                '/api/results',
                'GET',
                500,
                errorType,
                'Server error',
                '{"error":"failed"}',
                'Pending'
            )
        );

        logs.add(
            OneCall24Helper.createErrorLog(
                'TEST002',
                '/api/confirm',
                'POST',
                400,
                errorType,
                'Invalid candidate',
                '{"error":"invalid"}',
                'Retry Scheduled'
            )
        );

        Test.startTest();

        OneCall24Helper.saveErrorLogs(logs);

        Test.stopTest();

        List<OneCall24_Error_Log__c> savedLogs = [
            SELECT Id, Candidate_Reference__c, Retry_Status__c
            FROM OneCall24_Error_Log__c
        ];

        System.assertEquals(2, savedLogs.size());
    }

    // Test saveErrorLogs with null and empty lists
    @IsTest
    static void testSaveErrorLogsEmpty() {

        Test.startTest();

        OneCall24Helper.saveErrorLogs(null);

        OneCall24Helper.saveErrorLogs(
            new List<OneCall24_Error_Log__c>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM OneCall24_Error_Log__c]
        );
    }

    // Test resolveErrorLogs()
    @IsTest
    static void testResolveErrorLogs() {

        String errorType = getValidErrorType();

        List<OneCall24_Error_Log__c> logs =
            new List<OneCall24_Error_Log__c>();

        logs.add(
            OneCall24Helper.createErrorLog(
                'TEST001',
                '/api/results',
                'GET',
                500,
                errorType,
                'Server error',
                '{}',
                'Pending'
            )
        );

        logs.add(
            OneCall24Helper.createErrorLog(
                'TEST002',
                '/api/confirm',
                'POST',
                500,
                errorType,
                'Server error',
                '{}',
                'Retry Scheduled'
            )
        );

        logs.add(
            OneCall24Helper.createErrorLog(
                'TEST003',
                '/api/reset',
                'POST',
                500,
                errorType,
                'Server error',
                '{}',
                'Retrying'
            )
        );

        logs.add(
            OneCall24Helper.createErrorLog(
                'TEST004',
                '/api/results',
                'GET',
                500,
                errorType,
                'Server error',
                '{}',
                'Failed'
            )
        );

        insert logs;

        Test.startTest();

        OneCall24Helper.resolveErrorLogs(
            new List<String>{
                'TEST001',
                'TEST002',
                'TEST003',
                'TEST004'
            }
        );

        Test.stopTest();

        Map<String, OneCall24_Error_Log__c> resultMap =
            new Map<String, OneCall24_Error_Log__c>();

        for (OneCall24_Error_Log__c record : [
            SELECT Candidate_Reference__c, Retry_Status__c
            FROM OneCall24_Error_Log__c
        ]) {
            resultMap.put(
                record.Candidate_Reference__c,
                record
            );
        }

        System.assertEquals(
            'Success',
            resultMap.get('TEST001').Retry_Status__c
        );

        System.assertEquals(
            'Success',
            resultMap.get('TEST002').Retry_Status__c
        );

        System.assertEquals(
            'Success',
            resultMap.get('TEST003').Retry_Status__c
        );

        System.assertEquals(
            'Failed',
            resultMap.get('TEST004').Retry_Status__c
        );
    }

    // Test resolveErrorLogs with null and empty lists
    @IsTest
    static void testResolveErrorLogsEmpty() {

        Test.startTest();

        OneCall24Helper.resolveErrorLogs(null);

        OneCall24Helper.resolveErrorLogs(
            new List<String>()
        );

        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM OneCall24_Error_Log__c]
        );
    }
}