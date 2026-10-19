@IsTest
private class LeaseExpiryReminderBatchTest {
    @TestSetup
    static void setup() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        List<Property__c> props = TestDataFactory.createProperties(3);
        Tenant__c tenant = TestDataFactory.createTenant('tenant@example.com');
        insert new List<Lease_Agreement__c>{
            TestDataFactory.buildLease(props[0].Id, tenant.Id, Date.today().addMonths(1)),
            TestDataFactory.buildLease(props[1].Id, tenant.Id, Date.today().addDays(1)),
            TestDataFactory.buildLease(props[2].Id, tenant.Id, Date.today().addDays(10))
        };
    }

    @IsTest
    static void selectsOnlyLeasesDueForReminder() {
        LeaseExpiryReminderBatch batch = new LeaseExpiryReminderBatch();
        Test.startTest();
        Database.QueryLocator locator = batch.start(null);
        List<Lease_Agreement__c> due = new List<Lease_Agreement__c>();
        Database.QueryLocatorIterator it = locator.iterator();
        while (it.hasNext()) {
            due.add((Lease_Agreement__c) it.next());
        }
        batch.execute(null, due);
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(2, due.size());
        Assert.areEqual(1, emailInvocations, 'Emails are sent in a single bulk call');
    }

    @IsTest
    static void buildsReminderEmails() {
        for (Lease_Agreement__c lease : [
            SELECT Id, Name, End_Date__c, Property__r.Name, Property__r.Property_Name__c, Tenant__r.Name, Tenant__r.Email__c
            FROM Lease_Agreement__c
        ]) {
            Messaging.SingleEmailMessage email = LeaseExpiryReminderBatch.buildEmail(lease);
            Assert.areEqual('tenant@example.com', email.getToAddresses()[0]);
            if (lease.End_Date__c == Date.today().addDays(1)) {
                Assert.isTrue(email.getSubject().startsWith('Final reminder'));
            }
        }
    }

    @IsTest
    static void runsAsScheduledBatch() {
        Test.startTest();
        String jobId = System.schedule('Lease reminder test', '0 0 7 * * ?', new LeaseExpiryReminderBatch());
        new LeaseExpiryReminderBatch().execute((SchedulableContext) null);
        Test.stopTest();
        Assert.isNotNull(jobId);
        Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
    }
}