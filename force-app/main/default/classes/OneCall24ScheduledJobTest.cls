@isTest
private class OneCall24ScheduledJobTest {

    // Cron: every day at 2 AM
    private static final String CRON_EXP = '0 0 2 * * ?';

    // Generic mock so the test keeps working when the API call is uncommented
    private class OneCall24HttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"results":[]}');
            res.setStatusCode(200);
            return res;
        }
    }

    // Calls execute() directly and confirms it completes without throwing
    @isTest
    static void testExecuteDirectly() {
        Test.setMock(HttpCalloutMock.class, new OneCall24HttpMock());

        Boolean threw = false;
        Test.startTest();
        try {
            new OneCall24ScheduledJob().execute(null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'execute() should not throw.');
    }

    // Schedules the job, lets it run at stopTest, and checks the cron settings
    @isTest
    static void testScheduleJob() {
        Test.setMock(HttpCalloutMock.class, new OneCall24HttpMock());

        Test.startTest();
        String jobId = System.schedule(
            'OneCall24 Scheduled Job Test',
            CRON_EXP,
            new OneCall24ScheduledJob()
        );
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(CRON_EXP, ct.CronExpression, 'Cron expression should match.');
        System.assertNotEquals(null, ct.NextFireTime, 'Job should have a next fire time.');
    }
}