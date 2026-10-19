/**
 * @description Geocodes property addresses asynchronously (OpenStreetMap Nominatim) and stores
 * the result in Location__c. Processes records in chunks and chains itself for bulk loads.
 */
public with sharing class GeocodingService implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final String ENDPOINT = 'https://nominatim.openstreetmap.org/search';
    // Up to 3 callouts per record must stay under the 100-callout transaction limit.
    @TestVisible
    private static final Integer CHUNK_SIZE = 30;

    private final List<Id> propertyIds;

    public GeocodingService(Set<Id> propertyIds) {
        this.propertyIds = new List<Id>(propertyIds);
    }

    public void execute(QueueableContext context) {
        List<Id> current = new List<Id>();
        Set<Id> remaining = new Set<Id>();
        for (Id propId : propertyIds) {
            if (current.size() < CHUNK_SIZE) {
                current.add(propId);
            } else {
                remaining.add(propId);
            }
        }

        List<Property__c> updates = new List<Property__c>();
        for (Property__c prop : [
            SELECT Id, Address__c, City__c, State__c, Postal_Code__c, Country__c
            FROM Property__c
            WHERE Id IN :current
        ]) {
            Location loc = geocodeWithFallback(prop);
            if (loc != null) {
                updates.add(
                    new Property__c(
                        Id = prop.Id,
                        Location__Latitude__s = loc.getLatitude(),
                        Location__Longitude__s = loc.getLongitude()
                    )
                );
            }
        }
        if (!updates.isEmpty()) {
            // Partial success so one invalid legacy record does not block the rest.
            Database.update(updates, false);
        }
        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new GeocodingService(remaining));
        }
    }

    @TestVisible
    private static String buildAddress(Property__c prop) {
        return joinParts(
            new List<String>{ prop.Address__c, prop.City__c, prop.State__c, prop.Postal_Code__c, prop.Country__c }
        );
    }

    // Free-text street lines often fail to resolve, so retry with progressively broader queries.
    @TestVisible
    private static Location geocodeWithFallback(Property__c prop) {
        List<String> queries = new List<String>{
            buildAddress(prop),
            joinParts(new List<String>{ prop.City__c, prop.State__c, prop.Postal_Code__c, prop.Country__c }),
            joinParts(new List<String>{ prop.City__c, prop.State__c, prop.Country__c })
        };
        for (String query : queries) {
            Location loc = geocode(query);
            if (loc != null) {
                return loc;
            }
        }
        return null;
    }

    private static String joinParts(List<String> values) {
        List<String> parts = new List<String>();
        for (String part : values) {
            if (String.isNotBlank(part)) {
                parts.add(part.replaceAll('[\\r\\n]+', ' ').trim());
            }
        }
        return String.join(parts, ', ');
    }

    /**
     * @description Returns the coordinates for an address, or null when it cannot be resolved.
     */
    public static Location geocode(String address) {
        if (String.isBlank(address)) {
            return null;
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT + '?format=json&limit=1&q=' + EncodingUtil.urlEncode(address, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('User-Agent', 'RealEstate-PMS-Salesforce/1.0');
        req.setTimeout(20000);
        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return null;
            }
            List<Object> results = (List<Object>) JSON.deserializeUntyped(res.getBody());
            if (results.isEmpty()) {
                return null;
            }
            Map<String, Object> first = (Map<String, Object>) results[0];
            return Location.newInstance(
                Decimal.valueOf((String) first.get('lat')),
                Decimal.valueOf((String) first.get('lon'))
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Geocoding failed: ' + e.getMessage());
            return null;
        }
    }
}