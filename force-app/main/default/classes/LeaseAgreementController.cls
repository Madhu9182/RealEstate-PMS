/**
 * @description Lease agreement record page actions: load details for the PDF, mark the PDF as
 * generated and email the (client-side jsPDF generated) PDF to the tenant.
 */
public with sharing class LeaseAgreementController {
    // Base64 of ~3 MB, keeps the request well under Apex heap and email attachment limits.
    private static final Integer MAX_PDF_BASE64_LENGTH = 4000000;

    @AuraEnabled(cacheable=true)
    public static Lease_Agreement__c getLeaseDetails(Id leaseId) {
        List<Lease_Agreement__c> leases = [
            SELECT
                Id, Name, Terms__c, Agreed_Monthly_Rent__c, Start_Date__c, End_Date__c, PDF_Generated__c,
                Property__r.Name, Property__r.Property_Name__c, Property__r.Address__c, Property__r.City__c,
                Property__r.State__c, Property__r.Postal_Code__c, Property__r.Country__c,
                Tenant__r.Name, Tenant__r.Email__c, Tenant__r.Phone_Number__c
            FROM Lease_Agreement__c
            WHERE Id = :leaseId
            WITH USER_MODE
        ];
        if (leases.isEmpty()) {
            throw new AuraHandledException('Lease agreement not found.');
        }
        return leases[0];
    }

    @AuraEnabled
    public static void markPdfGenerated(Id leaseId) {
        try {
            Database.update(new Lease_Agreement__c(Id = leaseId, PDF_Generated__c = true), AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Saves the PDF on the lease record and emails it to the tenant.
     */
    @AuraEnabled
    public static void sendLeaseToTenant(Id leaseId, String pdfBase64) {
        if (String.isBlank(pdfBase64) || pdfBase64.length() > MAX_PDF_BASE64_LENGTH) {
            throw new AuraHandledException('The lease agreement PDF is missing or too large.');
        }
        Lease_Agreement__c lease = getLeaseDetails(leaseId);
        if (lease.Tenant__r == null || String.isBlank(lease.Tenant__r.Email__c)) {
            throw new AuraHandledException('The tenant does not have an email address.');
        }

        Blob pdf;
        try {
            pdf = EncodingUtil.base64Decode(pdfBase64);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid PDF content.');
        }
        String fileName = 'Lease Agreement - ' + lease.Name + '.pdf';

        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(fileName);
        attachment.setContentType('application/pdf');
        attachment.setBody(pdf);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ lease.Tenant__r.Email__c });
        email.setSubject('Your Lease Agreement - ' + lease.Name);
        email.setPlainTextBody(
            'Dear ' + lease.Tenant__r.Name + ',\n\n' +
            'Please find attached your lease agreement for ' +
            propertyLabel(lease) + '.\n\nRegards,\nProperty Management Team'
        );
        email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
        email.setSaveAsActivity(false);

        try {
            insert as user new ContentVersion(
                Title = fileName.removeEnd('.pdf'),
                PathOnClient = fileName,
                VersionData = pdf,
                FirstPublishLocationId = lease.Id
            );
            Database.update(new Lease_Agreement__c(Id = lease.Id, PDF_Generated__c = true), AccessLevel.USER_MODE);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            throw new AuraHandledException('Unable to send the lease agreement: ' + e.getMessage());
        }
    }

    public static String propertyLabel(Lease_Agreement__c lease) {
        if (lease.Property__r == null) {
            return 'your property';
        }
        return String.isNotBlank(lease.Property__r.Property_Name__c)
            ? lease.Property__r.Property_Name__c
            : lease.Property__r.Name;
    }
}