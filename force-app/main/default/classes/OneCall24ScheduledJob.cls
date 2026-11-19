/**
 * @Class Name    : OneCall24ScheduledJob
 * @Author        : Devesh Sharma
 * @Purpose       : Schedules periodic OneCall24 API synchronization.
 * @Description   : Implements Schedulable and
 *                  Database.AllowsCallouts interfaces to
 *                  execute the scheduled integration process.
 */

global class OneCall24ScheduledJob
    implements Schedulable, Database.AllowsCallouts {
    global void execute(SchedulableContext sc) {
        System.debug('===== ONECALL24 SCHEDULED JOB STARTED =====');
        try {
            OneCall24ApiService.fetchResults();
            System.debug('OneCall24 API sync initiated successfully.');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,'OneCall24 Scheduled Job Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR,'Error Line: ' + e.getLineNumber());
        }
        System.debug('===== ONECALL24 SCHEDULED JOB COMPLETED =====');
    }
}