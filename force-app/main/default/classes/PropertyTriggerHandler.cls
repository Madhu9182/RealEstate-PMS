/**
 * @description Property trigger logic: keeps status in sync with tenant assignment, creates
 * "Generate Lease Agreement" tasks and queues address geocoding. Fully bulkified.
 */
public with sharing class PropertyTriggerHandler {
    public static final String STATUS_OCCUPIED = 'Occupied';
    public static final String STATUS_AVAILABLE = 'Available';
    @TestVisible
    private static Boolean skipGeocoding = false;

    public static void run(System.TriggerOperation operation, List<Property__c> newList, Map<Id, Property__c> oldMap) {
        switch on operation {
            when BEFORE_INSERT, BEFORE_UPDATE {
                syncNameWithPropertyName(newList, oldMap);
                syncStatusWithTenant(newList, oldMap);
            }
            when AFTER_INSERT, AFTER_UPDATE {
                createLeaseAgreementTasks(newList, oldMap);
                queueGeocoding(newList, oldMap);
            }
        }
    }

    // Record name drives lookups, related lists and reports, so show the property name there.
    private static void syncNameWithPropertyName(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        for (Property__c prop : newList) {
            Property__c old = oldMap == null ? null : oldMap.get(prop.Id);
            Boolean propertyNameChanged = old == null || prop.Property_Name__c != old.Property_Name__c;
            if (propertyNameChanged && String.isNotBlank(prop.Property_Name__c)) {
                prop.Name = prop.Property_Name__c.left(80);
            } else if (old != null && prop.Name != old.Name && String.isNotBlank(prop.Name)) {
                prop.Property_Name__c = prop.Name;
            }
        }
    }

    private static void syncStatusWithTenant(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        for (Property__c prop : newList) {
            Property__c old = oldMap == null ? null : oldMap.get(prop.Id);
            Boolean tenantChanged = old == null ? prop.Tenant__c != null : prop.Tenant__c != old.Tenant__c;
            if (!tenantChanged) {
                continue;
            }
            prop.Status__c = prop.Tenant__c != null ? STATUS_OCCUPIED : STATUS_AVAILABLE;
        }
    }

    private static void createLeaseAgreementTasks(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        List<Task> tasks = new List<Task>();
        for (Property__c prop : newList) {
            Property__c old = oldMap == null ? null : oldMap.get(prop.Id);
            Boolean assigned = prop.Tenant__c != null && (old == null || old.Tenant__c != prop.Tenant__c);
            if (!assigned) {
                continue;
            }
            tasks.add(
                new Task(
                    Subject = 'Generate Lease Agreement',
                    Description = 'Property ' + prop.Name + ' has been assigned to a tenant. ' +
                        'Please generate the lease agreement.',
                    WhatId = prop.Id,
                    OwnerId = prop.OwnerId,
                    ActivityDate = Date.today().addDays(2),
                    Priority = 'High',
                    Status = 'Not Started'
                )
            );
        }
        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    private static void queueGeocoding(List<Property__c> newList, Map<Id, Property__c> oldMap) {
        Set<Id> toGeocode = new Set<Id>();
        for (Property__c prop : newList) {
            Property__c old = oldMap == null ? null : oldMap.get(prop.Id);
            if (old == null || addressChanged(prop, old)) {
                toGeocode.add(prop.Id);
            }
        }
        if (skipGeocoding || toGeocode.isEmpty() || System.isFuture() || System.isQueueable()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new GeocodingService(toGeocode));
        }
    }

    private static Boolean addressChanged(Property__c prop, Property__c old) {
        return prop.Address__c != old.Address__c ||
            prop.City__c != old.City__c ||
            prop.State__c != old.State__c ||
            prop.Postal_Code__c != old.Postal_Code__c ||
            prop.Country__c != old.Country__c;
    }
}