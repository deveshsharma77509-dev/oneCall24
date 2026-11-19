@isTest
private class OneCall24ExceptionHandlerTest {

    private static final String OPERATION = 'Fetch Results';
    private static final String ENDPOINT  = 'https://api.example.com/results';

    private static Integer logCount() {
        return [SELECT COUNT() FROM OneCall24_Error_Log__c];
    }

    // ---------- handleCalloutException ----------

    @isTest
    static void testHandleCalloutException_withCandidateRefs() {
        List<String> refs = new List<String>{ 'REF-001', 'REF-002' };
        Integer before = logCount();

        Test.startTest();
        OneCall24ExceptionHandler.handleCalloutException(
            new CalloutException('Callout failed'), OPERATION, ENDPOINT, refs
        );
        Test.stopTest();

        System.assertEquals(before + 2, logCount(), 'One log per candidate ref expected.');
    }

    @isTest
    static void testHandleCalloutException_nullRefs() {
        Integer before = logCount();

        Test.startTest();
        OneCall24ExceptionHandler.handleCalloutException(
            new CalloutException('Callout failed'), OPERATION, ENDPOINT, null
        );
        Test.stopTest();

        System.assertEquals(before + 1, logCount(), 'A single log expected when refs are null.');
    }

    @isTest
    static void testHandleCalloutException_emptyRefs() {
        Integer before = logCount();

        Test.startTest();
        OneCall24ExceptionHandler.handleCalloutException(
            new CalloutException('Callout failed'), OPERATION, ENDPOINT, new List<String>()
        );
        Test.stopTest();

        System.assertEquals(before + 1, logCount(), 'A single log expected when refs are empty.');
    }

    // ---------- handleException ----------

    @isTest
    static void testHandleException_withCandidateRefs() {
        Integer before = logCount();

        Test.startTest();
        try {
            Integer x = 1 / 0; // force a real exception so line number is populated
        } catch (Exception e) {
            OneCall24ExceptionHandler.handleException(
                e, OPERATION, ENDPOINT, new List<String>{ 'REF-001', 'REF-002', 'REF-003' }
            );
        }
        Test.stopTest();

        System.assertEquals(before + 3, logCount(), 'One log per candidate ref expected.');
    }

    @isTest
    static void testHandleException_nullRefs() {
        Integer before = logCount();

        Test.startTest();
        try {
            Integer x = 1 / 0;
        } catch (Exception e) {
            OneCall24ExceptionHandler.handleException(e, OPERATION, ENDPOINT, null);
        }
        Test.stopTest();

        System.assertEquals(before + 1, logCount(), 'A single log expected when refs are null.');
    }

    // ---------- Retry configuration ----------
    // Custom metadata records cannot be created in tests, so these tests
    // read the org's 'Default' record and assert against it.

    @isTest
    static void testIsRetryEnabled() {
        OneCall24_Settings__mdt settings = OneCall24_Settings__mdt.getInstance('Default');
        Boolean expected = settings != null && settings.Retry_Enabled__c;

        System.assertEquals(expected, OneCall24ExceptionHandler.isRetryEnabled(),
            'isRetryEnabled should reflect the Default custom metadata record.');
    }

    @isTest
    static void testGetMaxRetry() {
        OneCall24_Settings__mdt settings = OneCall24_Settings__mdt.getInstance('Default');
        Integer expected = (settings == null || settings.Max_Retry__c == null)
            ? 3
            : settings.Max_Retry__c.intValue();

        System.assertEquals(expected, OneCall24ExceptionHandler.getMaxRetry(),
            'getMaxRetry should reflect the Default custom metadata record (or 3 if unset).');
    }

    @isTest
    static void testIsRetryableStatusCode() {
        OneCall24_Settings__mdt settings = OneCall24_Settings__mdt.getInstance('Default');

        // A code that should never be configured as retryable
        System.assertEquals(false, OneCall24ExceptionHandler.isRetryableStatusCode(-1),
            'An unconfigured status code must not be retryable.');

        if (settings != null && settings.Retry_Enabled__c
            && String.isNotBlank(settings.Retryable_Status_Codes__c)) {
            // Every configured code should be reported as retryable
            for (String code : settings.Retryable_Status_Codes__c.split(',')) {
                System.assertEquals(true,
                    OneCall24ExceptionHandler.isRetryableStatusCode(Integer.valueOf(code.trim())),
                    'Configured status code ' + code.trim() + ' should be retryable.');
            }
        } else {
            // Retry disabled or no codes configured: nothing is retryable
            System.assertEquals(false, OneCall24ExceptionHandler.isRetryableStatusCode(503),
                'No status code should be retryable when retry is disabled or unconfigured.');
        }
    }
}