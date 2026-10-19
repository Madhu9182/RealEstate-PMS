/**
 * @description Daily job that emails tenants 1 month and 1 day before their lease ends.
 * Schedule with scripts/apex/scheduleJobs.apex.
 */
public with sharing class LeaseExpiryReminderBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext context) {
        Date oneMonth = Date.today().addMonths(1);
        Date oneDay = Date.today().addDays(1);
        return Database.getQueryLocator(
            [
                SELECT Id, Name, End_Date__c, Property__r.Name, Property__r.Property_Name__c,
                    Tenant__r.Name, Tenant__r.Email__c
                FROM Lease_Agreement__c
                WHERE End_Date__c IN (:oneMonth, :oneDay) AND Tenant__r.Email__c != NULL
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Lease_Agreement__c> leases) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Lease_Agreement__c lease : leases) {
            emails.add(buildEmail(lease));
        }
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'Lease expiry reminders processed.');
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new LeaseExpiryReminderBatch(), 100);
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildEmail(Lease_Agreement__c lease) {
        Boolean isFinalReminder = lease.End_Date__c == Date.today().addDays(1);
        String timing = isFinalReminder ? 'tomorrow' : 'in one month';

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ lease.Tenant__r.Email__c });
        email.setSubject(
            (isFinalReminder ? 'Final reminder: ' : 'Reminder: ') +
            'Your lease agreement ' + lease.Name + ' expires ' + timing
        );
        email.setPlainTextBody(
            'Dear ' + lease.Tenant__r.Name + ',\n\n' +
            'This is a reminder that your lease agreement ' + lease.Name + ' for ' +
            LeaseAgreementController.propertyLabel(lease) + ' expires ' + timing +
            ' (' + lease.End_Date__c.format() + ').\n' +
            'Please contact us if you would like to renew.\n\nRegards,\nProperty Management Team'
        );
        email.setSaveAsActivity(false);
        return email;
    }
}