trigger MaintenanceRequestTrigger on Maintenance_Request__c(before insert) {
    MaintenanceRequestTriggerHandler.assignVendors(Trigger.new);
}