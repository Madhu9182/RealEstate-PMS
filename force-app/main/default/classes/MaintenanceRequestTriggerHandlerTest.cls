@IsTest
private class MaintenanceRequestTriggerHandlerTest {
    @IsTest
    static void assignsToVendorWithLeastWorkload() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Property__c prop = TestDataFactory.createProperties(1)[0];
        List<Vendor__c> vendors = TestDataFactory.createVendors(3);

        // Vendor 0 already has 2 open requests; vendor 1 has 1; vendor 2 has a completed one only.
        insert new List<Maintenance_Request__c>{
            new Maintenance_Request__c(Name = 'Old 1', Property__c = prop.Id, Vendor__c = vendors[0].Id),
            new Maintenance_Request__c(Name = 'Old 2', Property__c = prop.Id, Vendor__c = vendors[0].Id),
            new Maintenance_Request__c(Name = 'Old 3', Property__c = prop.Id, Vendor__c = vendors[1].Id),
            new Maintenance_Request__c(
                Name = 'Old 4', Property__c = prop.Id, Vendor__c = vendors[2].Id, Status__c = 'Completed'
            )
        };

        Test.startTest();
        Maintenance_Request__c single = new Maintenance_Request__c(Name = 'New', Property__c = prop.Id);
        insert single;
        Test.stopTest();

        Maintenance_Request__c saved = [SELECT Vendor__c, Status__c FROM Maintenance_Request__c WHERE Id = :single.Id];
        Assert.areEqual(vendors[2].Id, saved.Vendor__c);
        Assert.areEqual('Open', saved.Status__c);
    }

    @IsTest
    static void distributesBulkRequestsEvenly() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Property__c prop = TestDataFactory.createProperties(1)[0];
        List<Vendor__c> vendors = TestDataFactory.createVendors(4);

        List<Maintenance_Request__c> requests = new List<Maintenance_Request__c>();
        for (Integer i = 0; i < 200; i++) {
            requests.add(new Maintenance_Request__c(Name = 'Req ' + i, Property__c = prop.Id, Status__c = 'Open'));
        }
        Test.startTest();
        insert requests;
        Test.stopTest();

        for (AggregateResult ar : [
            SELECT Vendor__c, COUNT(Id) total
            FROM Maintenance_Request__c
            GROUP BY Vendor__c
        ]) {
            Assert.areEqual(50, (Integer) ar.get('total'));
        }
    }

    @IsTest
    static void leavesRequestUnassignedWithoutVendors() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Property__c prop = TestDataFactory.createProperties(1)[0];
        Maintenance_Request__c req = new Maintenance_Request__c(Name = 'Lonely', Property__c = prop.Id);
        insert req;
        Assert.isNull([SELECT Vendor__c FROM Maintenance_Request__c WHERE Id = :req.Id].Vendor__c);
    }
}