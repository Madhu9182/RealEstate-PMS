@IsTest
private class PropertyTriggerHandlerTest {
    @IsTest
    static void assigningTenantCreatesTaskAndOccupiesProperty() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Tenant__c tenant = TestDataFactory.createTenant('tenant@example.com');
        List<Property__c> props = TestDataFactory.createProperties(200);

        Test.startTest();
        for (Property__c p : props) {
            p.Tenant__c = tenant.Id;
        }
        update props;
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Task WHERE Subject = 'Generate Lease Agreement']);
        Assert.areEqual(200, [SELECT COUNT() FROM Property__c WHERE Status__c = 'Occupied']);

        props[0].Tenant__c = null;
        update props[0];
        Assert.areEqual('Available', [SELECT Status__c FROM Property__c WHERE Id = :props[0].Id].Status__c);
    }

    @IsTest
    static void insertWithTenantCreatesTask() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Tenant__c tenant = TestDataFactory.createTenant('tenant@example.com');
        Property__c p = TestDataFactory.buildProperty('Rented');
        p.Tenant__c = tenant.Id;

        Test.startTest();
        insert p;
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :p.Id]);
        Property__c saved = [SELECT Name, Status__c FROM Property__c WHERE Id = :p.Id];
        Assert.areEqual('Occupied', saved.Status__c);
        Assert.areEqual('Rented', saved.Name, 'Record name mirrors the property name');

        p.Name = 'Renamed';
        update p;
        Assert.areEqual('Renamed', [SELECT Property_Name__c FROM Property__c WHERE Id = :p.Id].Property_Name__c);
    }

    @IsTest
    static void geocodesAddressOnInsertAndChange() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Property__c p = TestDataFactory.buildProperty('Geo');

        Test.startTest();
        insert p;
        Test.stopTest();

        Property__c saved = [SELECT Location__Latitude__s, Location__Longitude__s FROM Property__c WHERE Id = :p.Id];
        Assert.areEqual(12.971599, saved.Location__Latitude__s);
        Assert.areEqual(77.594566, saved.Location__Longitude__s);
    }

    @IsTest
    static void addressChangeRequeuesGeocoding() {
        Property__c p = TestDataFactory.buildProperty('Geo');
        p.Location__Latitude__s = 1;
        p.Location__Longitude__s = 1;
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        insert p;

        Test.startTest();
        p.City__c = 'Mysuru';
        update p;
        Test.stopTest();

        Assert.areEqual(
            12.971599,
            [SELECT Location__Latitude__s FROM Property__c WHERE Id = :p.Id].Location__Latitude__s
        );
    }
}