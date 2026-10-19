@IsTest
public class TestDataFactory {
    private static final String USERNAME_SUFFIX = '@realestate-pms.test';

    /**
     * @description Standard user with the Real Estate PMS permission set, so USER_MODE code is tested
     * with the same FLS/CRUD a real user gets. Runs in its own context to avoid mixed DML.
     */
    public static User createPmsUser() {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
            u = new User(
                Alias = 'pmsuser',
                Email = 'pms.user@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'PMS User',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = p.Id,
                TimeZoneSidKey = 'Asia/Kolkata',
                Username = 'pms' + unique + USERNAME_SUFFIX
            );
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Real_Estate_PMS_User'].Id
            );
        }
        return u;
    }

    public static User getPmsUser() {
        return [SELECT Id FROM User WHERE Username LIKE :('%' + USERNAME_SUFFIX) LIMIT 1];
    }
    public static Property__c buildProperty(String name) {
        return new Property__c(
            Property_Name__c = name,
            Address__c = '1 Main Street',
            City__c = 'Bengaluru',
            State__c = 'Karnataka',
            Postal_Code__c = '560001',
            Country__c = 'India',
            Type__c = 'Residential',
            Status__c = 'Available',
            Furnishing_Status__c = 'Furnished',
            Price__c = 1000,
            Description__c = 'Test property'
        );
    }

    public static List<Property__c> createProperties(Integer count) {
        List<Property__c> props = new List<Property__c>();
        for (Integer i = 0; i < count; i++) {
            props.add(buildProperty('Property ' + i));
        }
        insert props;
        return props;
    }

    public static Tenant__c createTenant(String email) {
        Tenant__c tenant = new Tenant__c(Name = 'Test Tenant', Email__c = email, Phone_Number__c = '9999999999');
        insert tenant;
        return tenant;
    }

    public static Lease_Agreement__c buildLease(Id propertyId, Id tenantId, Date endDate) {
        return new Lease_Agreement__c(
            Name = 'LA-Test',
            Property__c = propertyId,
            Tenant__c = tenantId,
            Agreed_Monthly_Rent__c = 1000,
            Start_Date__c = endDate.addYears(-1),
            End_Date__c = endDate,
            Terms__c = 'Standard terms'
        );
    }

    public static List<Vendor__c> createVendors(Integer count) {
        List<Vendor__c> vendors = new List<Vendor__c>();
        for (Integer i = 0; i < count; i++) {
            vendors.add(new Vendor__c(Name = 'Vendor ' + i, Email__c = 'vendor' + i + '@example.com'));
        }
        insert vendors;
        return vendors;
    }

    public class GeocodeMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;

        public GeocodeMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    public static GeocodeMock successMock() {
        return new GeocodeMock(200, '[{"lat":"12.971599","lon":"77.594566"}]');
    }
}