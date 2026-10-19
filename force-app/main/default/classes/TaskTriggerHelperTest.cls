@IsTest
private class TaskTriggerHelperTest {
    @IsTest
    static void updatesAccountForContactTasksAndIgnoresTasksWithoutWho() {
        Account acc = new Account(Name = 'Acme');
        insert acc;
        Contact con = new Contact(LastName = 'Doe', AccountId = acc.Id);
        insert con;

        Test.startTest();
        insert new List<Task>{
            new Task(Subject = 'Call', WhoId = con.Id),
            new Task(Subject = 'No who')
        };
        Test.stopTest();

        Assert.areEqual(Date.today(), [SELECT SLAExpirationDate__c FROM Account WHERE Id = :acc.Id].SLAExpirationDate__c);
    }
}