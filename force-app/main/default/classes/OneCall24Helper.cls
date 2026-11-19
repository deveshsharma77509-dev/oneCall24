/**
 * @Class Name    : OneCall24Helper
 * @Author        : Devesh Sharma
 * @Purpose       : Provides reusable utility methods.
 * @Description   : Handles API response data conversion,
 *                  error log creation, bulk error log insertion,
 *                  text truncation and error log resolution.
 */

public class OneCall24Helper {
    // Convert API value to String
    public static String getString(Map<String, Object> data,String key){
        Object value = data.get(key);
        return value == null ? null : String.valueOf(value);
    }

    // Convert API value to Decimal
    public static Decimal getDecimal(Map<String, Object> data,String key){
        Object value = data.get(key);
        return value == null || String.isBlank(String.valueOf(value))? null: Decimal.valueOf(String.valueOf(value));}

    // Convert API value to Datetime
    public static Datetime getDateTime(Map<String, Object> data,String key){
        Object value = data.get(key);
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        return (Datetime) JSON.deserialize(JSON.serialize(String.valueOf(value)),Datetime.class);
    }

    // Create Error Log
    public static OneCall24_Error_Log__c createErrorLog(
        String candidateRef,
        String endpoint,
        String operation,
        Integer statusCode,
        String errorType,
        String errorMessage,
        String responseBody,
        String retryStatus
    ) {
        return new OneCall24_Error_Log__c(
            Candidate_Reference__c = truncateText(candidateRef, 100),
            API_Endpoint__c = truncateText(endpoint, 255),
            Operation__c = truncateText(operation, 100),
            HTTP_Status_Code__c = statusCode,
            Error_Type__c = errorType,
            Error_Message__c = truncateText(errorMessage, 32000),
            Response_Body__c = truncateText(responseBody, 32000),
            Occurred_At__c = System.now(),
            Retry_Status__c = retryStatus
        );
    }

   
    public static void saveErrorLogs(List<OneCall24_Error_Log__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.insert(logs, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug('ERROR LOG INSERT FAILED: ' + err.getMessage());
                }
            }
        }
    }

    // Resolve Previous Error Logs
    public static void resolveErrorLogs(List<String> refs) {
        if (refs == null || refs.isEmpty()) {
            return;
        }
        List<OneCall24_Error_Log__c> logs = [
            SELECT Id, Retry_Status__c FROM OneCall24_Error_Log__c WHERE Candidate_Reference__c IN :refs
            AND Retry_Status__c IN ('Pending','Retry Scheduled','Retrying')];
        for (OneCall24_Error_Log__c logRecord : logs) {
            logRecord.Retry_Status__c = 'Success';
        }
        if (!logs.isEmpty()) {
            Database.update(logs, false);
        }
    }

    // Common Text Length Control
    private static String truncateText(String value,Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength): value;
    }
}