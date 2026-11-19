public class OneCall24ApiClient {

    // GET Results API
    public static HttpResponse getResults() {
        OneCall24_Settings__mdt settings = getSettings();
        return sendRequest('GET',settings.Results_Path__c,null);
    }

    // POST Confirm API
    public static HttpResponse confirmCandidates(List<String> candidateRefs) {
        if (candidateRefs == null || candidateRefs.isEmpty()) {
            throw new IllegalArgumentException('Candidate references cannot be empty.');
        }
        OneCall24_Settings__mdt settings = getSettings();
        Map<String, Object> requestBody =new Map<String, Object>{'refs' => candidateRefs};
        return sendRequest('POST',settings.Confirm_Path__c,JSON.serialize(requestBody));
        }

        // POST Reset API
    public static HttpResponse resetConfirmations() {
        OneCall24_Settings__mdt settings = getSettings();
        return sendRequest('POST',settings.Reset_Path__c,null);
       }
    
    // Common HTTP Request
    private static HttpResponse sendRequest(String method,String endpoint, String body) {
        OneCall24_Settings__mdt settings = getSettings();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:OneCall24_API' + endpoint);
        request.setMethod(method);
        request.setTimeout(settings.Timeout__c.intValue());
        request.setHeader('Content-Type','application/json');
        if (body != null) {
            request.setBody(body);
        }
        return new Http().send(request);
    }

    // Get Custom Metadata Configuration
    private static OneCall24_Settings__mdt getSettings() {
        OneCall24_Settings__mdt settings =OneCall24_Settings__mdt.getInstance('Default');
        if (settings == null ||settings.Timeout__c == null ||settings.Timeout__c <= 0) {
            throw new IllegalArgumentException('OneCall24 Default configuration is missing or invalid.');
        }
        return settings;
    }
}