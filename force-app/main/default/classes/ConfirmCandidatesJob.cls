public class ConfirmCandidatesJob
    implements Queueable, Database.AllowsCallouts {

    private List<String> candidateRefs;

    public ConfirmCandidatesJob(List<String> refs) {
        this.candidateRefs = refs;
    }

    public void execute(QueueableContext context) {

        if (candidateRefs == null || candidateRefs.isEmpty()) {
            System.debug('No candidate references to confirm.');
            return;
        }

        String endpoint =
            'callout:OneCall24_API/confirm';

        try {

            Http http = new Http();
            HttpRequest request = new HttpRequest();

            request.setEndpoint(endpoint);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setTimeout(120000);

            request.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'refs' => candidateRefs
                    }
                )
            );

            HttpResponse response = http.send(request);

            Integer statusCode = response.getStatusCode();
            String responseBody = response.getBody();

            System.debug('CONFIRM STATUS: ' + statusCode);
            System.debug('CONFIRM RESPONSE: ' + responseBody);

            if (statusCode < 200 || statusCode >= 300) {

                saveConfirmErrors(
                    candidateRefs,
                    endpoint,
                    statusCode,
                    'API Failure',
                    'Confirm API returned HTTP status ' + statusCode,
                    responseBody,
                    'Retry Scheduled'
                );

                return;
            }

            Map<String, Object> responseMap =
                (Map<String, Object>) JSON.deserializeUntyped(
                    responseBody
                );

            List<Object> unknownRefs =
                (List<Object>) responseMap.get('unknown');

            Set<String> unknownSet = new Set<String>();

            if (unknownRefs != null) {

                for (Object ref : unknownRefs) {
                    unknownSet.add(String.valueOf(ref));
                }
            }

            List<String> confirmedRefs = new List<String>();

            for (String ref : candidateRefs) {

                if (unknownSet.contains(ref)) {

                    saveConfirmErrors(
                        new List<String>{ ref },
                        endpoint,
                        statusCode,
                        'Record Failure',
                        'Confirm API returned this reference in unknown list.',
                        responseBody,
                        'Failed'
                    );

                } else {

                    confirmedRefs.add(ref);
                }
            }

            resolveConfirmLogs(confirmedRefs);

            System.debug(
                'CONFIRMED COUNT: ' + confirmedRefs.size()
            );

            System.debug(
                'UNKNOWN COUNT: ' + unknownSet.size()
            );

        } catch (Exception ex) {

            saveConfirmErrors(
                candidateRefs,
                endpoint,
                null,
                'Exception',
                ex.getMessage() +
                ' | Line Number: ' + ex.getLineNumber(),
                null,
                'Retry Scheduled'
            );

            System.debug(
                'CONFIRM QUEUEABLE EXCEPTION: ' +
                ex.getMessage() +
                ' | Line: ' + ex.getLineNumber()
            );
        }
    }

    // ---------------- ERROR LOG METHODS ----------------

    private static void saveConfirmErrors(
        List<String> refs,
        String endpoint,
        Integer statusCode,
        String errorType,
        String errorMessage,
        String responseBody,
        String retryStatus
    ) {

        List<OneCall24_Error_Log__c> logs =
            new List<OneCall24_Error_Log__c>();

        for (String ref : refs) {

            OneCall24_Error_Log__c logRecord =
                new OneCall24_Error_Log__c();

            logRecord.Candidate_Reference__c =
                truncateText(ref, 100);

            logRecord.API_Endpoint__c =
                truncateText(endpoint, 255);

            logRecord.Operation__c = 'POST /confirm';

            logRecord.HTTP_Status_Code__c = statusCode;

            logRecord.Error_Type__c = errorType;

            logRecord.Error_Message__c =
                truncateText(errorMessage, 32000);

            logRecord.Response_Body__c =
                truncateText(responseBody, 32000);

            logRecord.Occurred_At__c = System.now();

            logRecord.Retry_Status__c = retryStatus;

            logs.add(logRecord);
        }

        if (!logs.isEmpty()) {

            Database.SaveResult[] results =
                Database.insert(logs, false);

            for (Integer i = 0; i < results.size(); i++) {

                if (!results[i].isSuccess()) {

                    for (Database.Error err : results[i].getErrors()) {

                        System.debug(
                            'CONFIRM ERROR LOG INSERT FAILED: ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }

    private static void resolveConfirmLogs(List<String> refs) {

        if (refs == null || refs.isEmpty()) {
            return;
        }

        List<OneCall24_Error_Log__c> oldLogs = [
            SELECT Id, Retry_Status__c
            FROM OneCall24_Error_Log__c
            WHERE Candidate_Reference__c IN :refs
            AND Retry_Status__c IN (
                'Pending',
                'Retry Scheduled',
                'Retrying'
            )
        ];

        for (OneCall24_Error_Log__c logRecord : oldLogs) {
            logRecord.Retry_Status__c = 'Success';
        }

        if (!oldLogs.isEmpty()) {
            Database.update(oldLogs, false);
        }
    }

    private static String truncateText(
        String value,
        Integer maxLength
    ) {

        if (value == null) {
            return null;
        }

        return value.length() > maxLength
            ? value.substring(0, maxLength)
            : value;
    }
}