/**
 * @description Server-side logic for listing (paginated + filtered) and creating properties.
 */
public with sharing class PropertyController {
    public static final Integer PAGE_SIZE = 25;
    // Keeps COUNT() well below the 50k query-row governor limit on large data volumes.
    private static final Integer MAX_COUNT = 40000;
    private static final String FIELDS =
        'Id, Name, Property_Name__c, Price__c, Status__c, Furnishing_Status__c, Type__c, ' +
        'City__c, State__c, Country__c, Tenant__c, Tenant__r.Name, ' +
        'Location__Latitude__s, Location__Longitude__s';

    public class PropertyFilter {
        @AuraEnabled
        public Decimal minPrice { get; set; }
        @AuraEnabled
        public Decimal maxPrice { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String furnishingStatus { get; set; }
        @AuraEnabled
        public Decimal distanceKm { get; set; }
        @AuraEnabled
        public Decimal latitude { get; set; }
        @AuraEnabled
        public Decimal longitude { get; set; }
    }

    public class PropertyPage {
        @AuraEnabled
        public List<Property__c> records;
        @AuraEnabled
        public Integer totalCount;
        @AuraEnabled
        public Integer pageSize = PAGE_SIZE;
    }

    /**
     * @description Returns one page (25 rows) of properties using keyset pagination on Id,
     * which avoids the 2,000 row OFFSET limit and scales to large data volumes.
     * @param filter     filter criteria (nullable)
     * @param direction  first | next | previous | last
     * @param cursorId   last Id of current page (next) or first Id of current page (previous)
     */
    @AuraEnabled(cacheable=true)
    public static PropertyPage getProperties(PropertyFilter filter, String direction, Id cursorId) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conditions = buildConditions(filter, binds);

            PropertyPage page = new PropertyPage();
            String whereClause = conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
            page.totalCount = Database.countQueryWithBinds(
                'SELECT COUNT() FROM Property__c' + whereClause + ' LIMIT ' + MAX_COUNT,
                binds,
                AccessLevel.USER_MODE
            );

            String sortOrder = 'ASC';
            Integer rowLimit = PAGE_SIZE;
            List<String> pageConditions = new List<String>(conditions);
            String dir = String.isBlank(direction) ? 'first' : direction.toLowerCase();

            if (dir == 'next' && cursorId != null) {
                pageConditions.add('Id > :cursorId');
                binds.put('cursorId', cursorId);
            } else if (dir == 'previous' && cursorId != null) {
                pageConditions.add('Id < :cursorId');
                binds.put('cursorId', cursorId);
                sortOrder = 'DESC';
            } else if (dir == 'last') {
                sortOrder = 'DESC';
                Integer remainder = Math.mod(page.totalCount, PAGE_SIZE);
                rowLimit = remainder == 0 ? PAGE_SIZE : remainder;
            }

            String query =
                'SELECT ' + FIELDS + ' FROM Property__c' +
                (pageConditions.isEmpty() ? '' : ' WHERE ' + String.join(pageConditions, ' AND ')) +
                ' ORDER BY Id ' + sortOrder +
                ' LIMIT ' + rowLimit;

            List<Property__c> records = Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
            if (sortOrder == 'DESC') {
                List<Property__c> ordered = new List<Property__c>();
                for (Integer i = records.size() - 1; i >= 0; i--) {
                    ordered.add(records[i]);
                }
                records = ordered;
            }
            page.records = records;
            return page;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    private static List<String> buildConditions(PropertyFilter filter, Map<String, Object> binds) {
        List<String> conditions = new List<String>();
        if (filter == null) {
            return conditions;
        }
        if (filter.minPrice != null) {
            conditions.add('Price__c >= :minPrice');
            binds.put('minPrice', filter.minPrice);
        }
        if (filter.maxPrice != null) {
            conditions.add('Price__c <= :maxPrice');
            binds.put('maxPrice', filter.maxPrice);
        }
        if (String.isNotBlank(filter.status)) {
            conditions.add('Status__c = :status');
            binds.put('status', filter.status);
        }
        if (String.isNotBlank(filter.furnishingStatus)) {
            conditions.add('Furnishing_Status__c = :furnishingStatus');
            binds.put('furnishingStatus', filter.furnishingStatus);
        }
        if (filter.distanceKm != null) {
            if (filter.latitude == null || filter.longitude == null) {
                throw new IllegalArgumentException('Your location is required to filter by distance.');
            }
            if (
                filter.distanceKm <= 0 ||
                Math.abs(filter.latitude) > 90 ||
                Math.abs(filter.longitude) > 180
            ) {
                throw new IllegalArgumentException('Invalid distance or location.');
            }
            // Values are typed Decimals, so string concatenation here cannot inject SOQL.
            conditions.add(
                'DISTANCE(Location__c, GEOLOCATION(' +
                filter.latitude + ', ' + filter.longitude + '), \'km\') < ' + filter.distanceKm
            );
        }
        return conditions;
    }

    /**
     * @description Creates a property and links the already uploaded images to it in a
     * single transaction. A property cannot be created without at least one image.
     */
    @AuraEnabled
    public static Id createPropertyWithImages(Property__c property, List<Id> contentDocumentIds) {
        if (property == null) {
            throw new AuraHandledException('Property details are required.');
        }
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw new AuraHandledException('Please upload at least one property image.');
        }

        // Only allow linking files the current user uploaded, so foreign documents cannot be attached.
        Map<Id, ContentDocument> docs = new Map<Id, ContentDocument>(
            [
                SELECT Id
                FROM ContentDocument
                WHERE Id IN :contentDocumentIds AND OwnerId = :UserInfo.getUserId()
                WITH USER_MODE
            ]
        );
        if (docs.size() != new Set<Id>(contentDocumentIds).size()) {
            throw new AuraHandledException('One or more images are invalid. Please upload them again.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            property.Id = null;
            Database.insert(property, AccessLevel.USER_MODE);

            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id docId : docs.keySet()) {
                links.add(
                    new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId = property.Id,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    )
                );
            }
            insert links;
            return property.Id;
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ContentVersion> getPropertyImages(Id propertyId) {
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :propertyId
            WITH USER_MODE
        ]) {
            docIds.add(link.ContentDocumentId);
        }
        return [
            SELECT Id, Title, FileExtension, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE
            WITH USER_MODE
            ORDER BY CreatedDate
        ];
    }
}