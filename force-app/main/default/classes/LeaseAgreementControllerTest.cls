@IsTest
private class LeaseAgreementControllerTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createPmsUser();
        Test.setMock(HttpCalloutMock.class, TestDataFactory.successMock());
        Property__c prop = TestDataFactory.createProperties(1)[0];
        Tenant__c tenant = TestDataFactory.createTenant('tenant@example.com');
        insert TestDataFactory.buildLease(prop.Id, tenant.Id, Date.today().addMonths(6));
    }

    @IsTest
    static void loadsDetailsAndMarksPdfGenerated() {
        Lease_Agreement__c lease = [SELECT Id FROM Lease_Agreement__c LIMIT 1];
        System.runAs(TestDataFactory.getPmsUser()) {
            Lease_Agreement__c details = LeaseAgreementController.getLeaseDetails(lease.Id);
            Assert.areEqual('tenant@example.com', details.Tenant__r.Email__c);
            Assert.areEqual('Property 0', LeaseAgreementController.propertyLabel(details));

            LeaseAgreementController.markPdfGenerated(lease.Id);
        }
        Assert.isTrue([SELECT PDF_Generated__c FROM Lease_Agreement__c WHERE Id = :lease.Id].PDF_Generated__c);
    }

    @IsTest
    static void sendsPdfToTenant() {
        Lease_Agreement__c lease = [SELECT Id FROM Lease_Agreement__c LIMIT 1];
        Integer emails;
        Test.startTest();
        System.runAs(TestDataFactory.getPmsUser()) {
            LeaseAgreementController.sendLeaseToTenant(lease.Id, EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4')));
            emails = Limits.getEmailInvocations();
        }
        Test.stopTest();

        Assert.areEqual(1, emails);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :lease.Id]);
        Assert.isTrue([SELECT PDF_Generated__c FROM Lease_Agreement__c WHERE Id = :lease.Id].PDF_Generated__c);
    }

    @IsTest
    static void validatesInput() {
        Lease_Agreement__c lease = [SELECT Id, Tenant__c FROM Lease_Agreement__c LIMIT 1];
        User pmsUser = TestDataFactory.getPmsUser();
        System.runAs(pmsUser) {
            assertInvalidPdfInputs(lease);
        }
        delete lease;
        System.runAs(pmsUser) {
            assertMissingLeaseFails(lease.Id);
        }
        Assert.areEqual('your property', LeaseAgreementController.propertyLabel(new Lease_Agreement__c()));
    }

    private static void assertInvalidPdfInputs(Lease_Agreement__c lease) {
        try {
            LeaseAgreementController.sendLeaseToTenant(lease.Id, '');
            Assert.fail('Expected an exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }

        update new Tenant__c(Id = lease.Tenant__c, Email__c = null);
        try {
            LeaseAgreementController.sendLeaseToTenant(lease.Id, 'JVBERi0=');
            Assert.fail('Expected an exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }

    private static void assertMissingLeaseFails(Id leaseId) {
        try {
            LeaseAgreementController.getLeaseDetails(leaseId);
            Assert.fail('Expected an exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        try {
            LeaseAgreementController.markPdfGenerated(leaseId);
            Assert.fail('Expected an exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }
}