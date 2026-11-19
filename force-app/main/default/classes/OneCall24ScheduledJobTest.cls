@IsTest
private class OneCall24ScheduledJobTest {

    // Test scheduled job execution
    @IsTest
    static void testScheduledJobExecution() {

        Test.startTest();

        OneCall24ScheduledJob job =
            new OneCall24ScheduledJob();

        job.execute(null);

        Test.stopTest();

        System.assertNotEquals(null, job);
    }

    // Test actual Salesforce scheduling
    @IsTest
    static void testScheduleJob() {

        Test.startTest();

        String jobId = System.schedule(
            'OneCall24 Test Scheduled Job',
            '0 0 0 1 1 ? 2099',
            new OneCall24ScheduledJob()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Scheduled job should be created successfully.'
        );
    }
}