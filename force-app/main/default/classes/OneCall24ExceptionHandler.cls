/**
 * @Class Name    : OneCall24ExceptionHandler
 * @Author        : Devesh Sharma
 * @Purpose       : Centralizes exception handling for
 *                  OneCall24 integration.
 * @Description   : Handles integration exceptions and manages
 *                  error logging to maintain reliable API
 *                  processing and troubleshooting.
 */

public class OneCall24ExceptionHandler {

    // Handle Callout Exception
    public static void handleCalloutException(
        CalloutException ex,
        String operation,
        String endpoint,
        List<String> candidateRefs
    ) {
        saveExceptionLog(ex.getMessage(),operation,endpoint,candidateRefs,'Callout Exception');
    }

    // Handle Other Exceptions
    public static void handleException(
        Exception ex,
        String operation,
        String endpoint,
        List<String> candidateRefs
    ) {
        saveExceptionLog(
            ex.getMessage() +
            ' | Line Number: ' + ex.getLineNumber(), operation,endpoint,candidateRefs,'Exception');
    }

    // Common Error Log Handling
    private static void saveExceptionLog(
        String message,
        String operation,
        String endpoint,
        List<String> candidateRefs,
        String errorType
    ) {

        List<OneCall24_Error_Log__c> logs =new List<OneCall24_Error_Log__c>();

        String retryStatus =isRetryEnabled() ? 'Retry Scheduled' : 'Not Required';
        if (candidateRefs == null || candidateRefs.isEmpty()) {
            logs.add(
                OneCall24Helper.createErrorLog(null,endpoint,operation,null,errorType,message,null,retryStatus)
            );
        } else {
            for (String ref : candidateRefs) {
                logs.add(
                    OneCall24Helper.createErrorLog(
                        ref,endpoint,operation,null,errorType,message,null,retryStatus)
                );
            }
        }

        OneCall24Helper.saveErrorLogs(logs);
    }

    // Read Retry Configuration
    public static Boolean isRetryEnabled() {
        OneCall24_Settings__mdt settings =OneCall24_Settings__mdt.getInstance('Default');
        return settings != null && settings.Retry_Enabled__c;
    }

    // Read Maximum Retry Count
    public static Integer getMaxRetry() {
        OneCall24_Settings__mdt settings = OneCall24_Settings__mdt.getInstance('Default');
        if (settings == null || settings.Max_Retry__c == null) {
            return 3;
        }
        return settings.Max_Retry__c.intValue();
    }

    // Check Retryable HTTP Status Code
    public static Boolean isRetryableStatusCode(Integer statusCode ) {
        OneCall24_Settings__mdt settings = OneCall24_Settings__mdt.getInstance('Default');
        if (settings == null ||!settings.Retry_Enabled__c ||String.isBlank(settings.Retryable_Status_Codes__c)) {
            return false;
        }
        List<String> statusCodes =settings.Retryable_Status_Codes__c.split(',');
        for (String code : statusCodes) {
            if (Integer.valueOf(code.trim()) == statusCode) {
                return true;
            }
        }
        return false;
    }
}