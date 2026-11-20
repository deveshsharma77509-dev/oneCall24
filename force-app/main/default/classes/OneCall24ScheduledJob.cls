/**
 * @Class Name    : OneCall24ScheduledJob
 * @Author        : Devesh Sharma
 * @Purpose       : Schedules periodic OneCall24 API synchronization.
 */

global class OneCall24ScheduledJob implements Schedulable {

    // Scheduled Apex Entry Point
    global void execute(SchedulableContext sc) {
        System.debug('===== ONECALL24 SCHEDULED JOB STARTED =====');

        try {
            syncOneCall24Data();
            System.debug('OneCall24 Sync Future Job Submitted.');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Scheduling Error: ' + e.getMessage());
        }

        System.debug('===== ONECALL24 SCHEDULED JOB COMPLETED =====');
    }

    // Execute API Callout Asynchronously
    @future(callout=true)
    public static void syncOneCall24Data() {
        System.debug('===== ONECALL24 API SYNC STARTED =====');

        try {
            OneCall24ApiService.fetchResults();

            System.debug('OneCall24 API Sync Completed Successfully.');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'OneCall24 API Sync Error: ' + e.getMessage());

            System.debug(LoggingLevel.ERROR,
                'Error Line: ' + e.getLineNumber());
        }

        System.debug('===== ONECALL24 API SYNC COMPLETED =====');
    }
}