@IsTest
private class OneCall24ExceptionHandlerTest {

    private static final String OPERATION = 'Fetch Results';
    private static final String ENDPOINT = '/results';

    // Get error logs by candidate reference
    private static List<OneCall24_Error_Log__c> getLogs(
        Set<String> refs
    ) {
        return [
            SELECT Id,
                   Candidate_Reference__c,
                   API_Endpoint__c,
                   Operation__c,
                   Error_Type__c,
                   Error_Message__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c IN :refs
        ];
    }

    // Get logs without candidate references
    private static List<OneCall24_Error_Log__c> getNullRefLogs() {
        return [
            SELECT Id,
                   Candidate_Reference__c,
                   Error_Type__c,
                   Operation__c,
                   API_Endpoint__c,
                   Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c = null
        ];
    }

    // Check active picklist value
    private static Boolean isActivePicklistValue(
        String fieldName,
        String expectedValue
    ) {

        Schema.SObjectField fieldToken =
            OneCall24_Error_Log__c.SObjectType.getDescribe()
            .fields.getMap().get(fieldName);

        if (fieldToken == null) {
            return false;
        }

        for (Schema.PicklistEntry entry :
            fieldToken.getDescribe().getPicklistValues()) {

            if (entry.isActive() &&
                entry.getValue() == expectedValue) {
                return true;
            }
        }

        return false;
    }

    // Validate picklist configuration
    @IsTest
    static void testRequiredPicklistValues() {

        System.assert(
            isActivePicklistValue(
                'Error_Type__c',
                'Callout Exception'
            ),
            'Add Callout Exception to Error_Type__c.'
        );

        System.assert(
            isActivePicklistValue(
                'Error_Type__c',
                'Exception'
            ),
            'Add Exception to Error_Type__c.'
        );

        System.assert(
            isActivePicklistValue(
                'Retry_Status__c',
                'Retry Scheduled'
            ),
            'Add Retry Scheduled to Retry_Status__c.'
        );

        System.assert(
            isActivePicklistValue(
                'Retry_Status__c',
                'Not Required'
            ),
            'Add Not Required to Retry_Status__c.'
        );
    }

    // Test Callout Exception with candidate references
    @IsTest
    static void testHandleCalloutException_withCandidateRefs() {

        Test.startTest();

        OneCall24ExceptionHandler.handleCalloutException(
            new CalloutException('Callout failed'),
            OPERATION,
            ENDPOINT,
            new List<String>{'TEST001', 'TEST002'}
        );

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs =
            getLogs(new Set<String>{'TEST001', 'TEST002'});

        System.assertEquals(2, logs.size());

        for (OneCall24_Error_Log__c logRecord : logs) {

            System.assertEquals(
                'Callout Exception',
                logRecord.Error_Type__c
            );

            System.assertEquals(
                OPERATION,
                logRecord.Operation__c
            );

            System.assertEquals(
                ENDPOINT,
                logRecord.API_Endpoint__c
            );
        }
    }

    // Test Callout Exception with null references
    @IsTest
    static void testHandleCalloutException_nullRefs() {

        Test.startTest();

        OneCall24ExceptionHandler.handleCalloutException(
            new CalloutException('Callout failed'),
            OPERATION,
            ENDPOINT,
            null
        );

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = getNullRefLogs();

        System.assertEquals(1, logs.size());

        System.assertEquals(
            'Callout Exception',
            logs[0].Error_Type__c
        );
    }

    // Test Callout Exception with empty references
    @IsTest
    static void testHandleCalloutException_emptyRefs() {

        Test.startTest();

        OneCall24ExceptionHandler.handleCalloutException(
            new CalloutException('Callout failed'),
            OPERATION,
            ENDPOINT,
            new List<String>()
        );

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = getNullRefLogs();

        System.assertEquals(1, logs.size());

        System.assertEquals(
            'Callout Exception',
            logs[0].Error_Type__c
        );
    }

    // Test Generic Exception with candidate references
    @IsTest
    static void testHandleException_withCandidateRefs() {

        Test.startTest();

        try {
            Integer value = 1 / 0;
        } catch (Exception ex) {

            OneCall24ExceptionHandler.handleException(
                ex,
                OPERATION,
                ENDPOINT,
                new List<String>{
                    'TEST003',
                    'TEST004',
                    'TEST005'
                }
            );
        }

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs =
            getLogs(new Set<String>{
                'TEST003',
                'TEST004',
                'TEST005'
            });

        System.assertEquals(3, logs.size());

        for (OneCall24_Error_Log__c logRecord : logs) {

            System.assertEquals(
                'Exception',
                logRecord.Error_Type__c
            );

            System.assert(
                logRecord.Error_Message__c.contains('Line Number:')
            );
        }
    }

    // Test Generic Exception with null references
    @IsTest
    static void testHandleException_nullRefs() {

        Test.startTest();

        try {
            Integer value = 1 / 0;
        } catch (Exception ex) {

            OneCall24ExceptionHandler.handleException(
                ex,
                OPERATION,
                ENDPOINT,
                null
            );
        }

        Test.stopTest();

        List<OneCall24_Error_Log__c> logs = getNullRefLogs();

        System.assertEquals(1, logs.size());

        System.assertEquals(
            'Exception',
            logs[0].Error_Type__c
        );
    }

    // Test Retry Enabled
    @IsTest
    static void testIsRetryEnabled() {

        OneCall24_Settings__mdt settings =
            OneCall24_Settings__mdt.getInstance('Default');

        Boolean expected =
            settings != null &&
            settings.Retry_Enabled__c;

        System.assertEquals(
            expected,
            OneCall24ExceptionHandler.isRetryEnabled()
        );
    }

    // Test Maximum Retry Count
    @IsTest
    static void testGetMaxRetry() {

        OneCall24_Settings__mdt settings =
            OneCall24_Settings__mdt.getInstance('Default');

        Integer expected =
            (settings == null || settings.Max_Retry__c == null)
            ? 3
            : settings.Max_Retry__c.intValue();

        System.assertEquals(
            expected,
            OneCall24ExceptionHandler.getMaxRetry()
        );
    }

    // Test Retryable HTTP Status Code
    @IsTest
    static void testIsRetryableStatusCode() {

        OneCall24_Settings__mdt settings =
            OneCall24_Settings__mdt.getInstance('Default');

        System.assertEquals(
            false,
            OneCall24ExceptionHandler.isRetryableStatusCode(-1)
        );

        if (settings != null &&
            settings.Retry_Enabled__c &&
            String.isNotBlank(settings.Retryable_Status_Codes__c)) {

            for (String code :
                settings.Retryable_Status_Codes__c.split(',')) {

                System.assertEquals(
                    true,
                    OneCall24ExceptionHandler.isRetryableStatusCode(
                        Integer.valueOf(code.trim())
                    )
                );
            }

        } else {

            System.assertEquals(
                false,
                OneCall24ExceptionHandler.isRetryableStatusCode(503)
            );
        }
    }
}