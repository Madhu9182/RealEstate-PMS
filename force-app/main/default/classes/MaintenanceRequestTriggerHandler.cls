/**
 * @description Auto-assigns new maintenance requests to the vendor with the least workload
 * (number of Open / In Progress requests). Bulk-safe: one aggregate query per transaction and
 * workload is tracked in memory while distributing a batch of requests.
 */
// Workload must consider every request regardless of the running user's sharing access.
public without sharing class MaintenanceRequestTriggerHandler {
    public static final Set<String> ACTIVE_STATUSES = new Set<String>{ 'Open', 'In Progress' };

    public static void assignVendors(List<Maintenance_Request__c> requests) {
        List<Maintenance_Request__c> unassigned = new List<Maintenance_Request__c>();
        for (Maintenance_Request__c req : requests) {
            if (String.isBlank(req.Status__c)) {
                req.Status__c = 'Open';
            }
            if (req.Vendor__c == null) {
                unassigned.add(req);
            }
        }
        if (unassigned.isEmpty()) {
            return;
        }

        Map<Id, Integer> workload = new Map<Id, Integer>();
        for (Vendor__c vendor : [SELECT Id FROM Vendor__c ORDER BY CreatedDate LIMIT 10000]) {
            workload.put(vendor.Id, 0);
        }
        if (workload.isEmpty()) {
            return;
        }
        for (AggregateResult ar : [
            SELECT Vendor__c vendorId, COUNT(Id) total
            FROM Maintenance_Request__c
            WHERE Vendor__c IN :workload.keySet() AND Status__c IN :ACTIVE_STATUSES
            GROUP BY Vendor__c
        ]) {
            workload.put((Id) ar.get('vendorId'), (Integer) ar.get('total'));
        }

        for (Maintenance_Request__c req : unassigned) {
            Id leastBusy;
            Integer lowest;
            for (Id vendorId : workload.keySet()) {
                Integer load = workload.get(vendorId);
                if (lowest == null || load < lowest) {
                    lowest = load;
                    leastBusy = vendorId;
                }
            }
            req.Vendor__c = leastBusy;
            workload.put(leastBusy, lowest + 1);
        }
    }
}