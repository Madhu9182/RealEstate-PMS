@IsTest
private class PropertyControllerTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createPmsUser();
        PropertyTriggerHandler.skipGeocoding = true;
        List<Property__c> props = new List<Property__c>();
        for (Integer i = 0; i < 60; i++) {
            Property__c p = TestDataFactory.buildProperty('Prop ' + i);
            p.Price__c = 100 * (i + 1);
            p.Status__c = Math.mod(i, 2) == 0 ? 'Available' : 'Occupied';
            p.Furnishing_Status__c = Math.mod(i, 3) == 0 ? 'Unfurnished' : 'Furnished';
            p.Location__Latitude__s = 12.97;
            p.Location__Longitude__s = 77.59 + (i * 0.1);
            props.add(p);
        }
        insert props;
    }

    @IsTest
    static void paginatesForwardAndBackward() {
        System.runAs(TestDataFactory.getPmsUser()) {
            PropertyController.PropertyPage first = PropertyController.getProperties(null, 'first', null);
            Assert.areEqual(60, first.totalCount);
            Assert.areEqual(25, first.records.size());

            PropertyController.PropertyPage second = PropertyController.getProperties(
                null, 'next', first.records[24].Id
            );
            Assert.areEqual(25, second.records.size());
            Assert.isTrue(second.records[0].Id > first.records[24].Id, 'Next page continues after cursor');

            PropertyController.PropertyPage back = PropertyController.getProperties(
                null, 'previous', second.records[0].Id
            );
            Assert.areEqual(first.records[0].Id, back.records[0].Id);

            PropertyController.PropertyPage last = PropertyController.getProperties(null, 'last', null);
            Assert.areEqual(10, last.records.size());
        }
    }

    @IsTest
    static void filtersByPriceStatusAndFurnishing() {
        PropertyController.PropertyFilter filter = new PropertyController.PropertyFilter();
        filter.minPrice = 1000;
        filter.maxPrice = 3000;
        filter.status = 'Available';
        filter.furnishingStatus = 'Furnished';

        System.runAs(TestDataFactory.getPmsUser()) {
            PropertyController.PropertyPage page = PropertyController.getProperties(filter, 'first', null);
            Assert.isTrue(page.totalCount > 0);
            for (Property__c p : page.records) {
                Assert.isTrue(p.Price__c >= 1000 && p.Price__c <= 3000);
                Assert.areEqual('Available', p.Status__c);
                Assert.areEqual('Furnished', p.Furnishing_Status__c);
            }
        }
    }

    @IsTest
    static void filtersByDistance() {
        PropertyController.PropertyFilter filter = new PropertyController.PropertyFilter();
        filter.distanceKm = 50;
        filter.latitude = 12.97;
        filter.longitude = 77.59;

        System.runAs(TestDataFactory.getPmsUser()) {
            PropertyController.PropertyPage page = PropertyController.getProperties(filter, 'first', null);
            // 0.1 degree longitude is ~10.8 km at this latitude, so only the first few are in range.
            Assert.isTrue(page.totalCount > 0 && page.totalCount < 60, 'Only nearby properties returned');
        }
    }

    @IsTest
    static void invalidDistanceFilterFails() {
        PropertyController.PropertyFilter noLocation = new PropertyController.PropertyFilter();
        noLocation.distanceKm = 10;
        PropertyController.PropertyFilter badLocation = new PropertyController.PropertyFilter();
        badLocation.distanceKm = 10;
        badLocation.latitude = 200;
        badLocation.longitude = 0;

        for (PropertyController.PropertyFilter filter : new List<PropertyController.PropertyFilter>{
            noLocation, badLocation
        }) {
            try {
                PropertyController.getProperties(filter, 'first', null);
                Assert.fail('Expected an exception');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
        }
    }

    @IsTest
    static void createsPropertyWithImages() {
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        System.runAs(TestDataFactory.getPmsUser()) {
            ContentVersion cv = new ContentVersion(
                Title = 'Front',
                PathOnClient = 'front.jpg',
                VersionData = Blob.valueOf('image')
            );
            insert cv;
            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

            Test.startTest();
            Id propId = PropertyController.createPropertyWithImages(
                TestDataFactory.buildProperty('With Image'),
                new List<Id>{ docId }
            );
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :propId]);
            Assert.areEqual(1, PropertyController.getPropertyImages(propId).size());
        }
    }

    @IsTest
    static void rejectsPropertyWithoutImages() {
        System.runAs(TestDataFactory.getPmsUser()) {
            try {
                PropertyController.createPropertyWithImages(TestDataFactory.buildProperty('No Image'), new List<Id>());
                Assert.fail('Expected an exception');
            } catch (AuraHandledException e) {
                Assert.areEqual(60, [SELECT COUNT() FROM Property__c]);
            }
            try {
                PropertyController.createPropertyWithImages(null, null);
                Assert.fail('Expected an exception');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
        }
    }

    @IsTest
    static void rejectsInvalidImagesAndInvalidProperty() {
        System.runAs(TestDataFactory.getPmsUser()) {
            ContentVersion cv = new ContentVersion(Title = 'Img', PathOnClient = 'img.png', VersionData = Blob.valueOf('x'));
            insert cv;
            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

            Property__c invalid = TestDataFactory.buildProperty('Invalid');
            invalid.State__c = null;
            try {
                PropertyController.createPropertyWithImages(invalid, new List<Id>{ docId });
                Assert.fail('Expected validation error');
            } catch (AuraHandledException e) {
                Assert.areEqual(60, [SELECT COUNT() FROM Property__c]);
            }

            try {
                PropertyController.createPropertyWithImages(
                    TestDataFactory.buildProperty('Bad doc'),
                    new List<Id>{ docId, '069000000000001' }
                );
                Assert.fail('Expected invalid image error');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
        }
    }
}