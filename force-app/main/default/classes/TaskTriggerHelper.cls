public with sharing class TaskTriggerHelper {
    public static void UpdateLastActivityDate(List<Task> newTasks) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Task t : newTasks) {
            if (t.WhoId != null && 'Contact'.equalsIgnoreCase(t.whoId.getSObjectType().getDescribe().getName())) {
                contactIds.add(t.WhoId);
            }
            /*
            if ('Account'.equalsIgnoreCase(t.WhatId.getSObjectType().getDescribe().getName())) {
                accountIds.add(t.whatId);
            }*/
        }
        Map<Id, Id> contactToAccountMap = new Map<Id, Id>();
        if (!contactIds.isEmpty()) {
            for (Contact con : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds]) {
                contactToAccountMap.put(con.Id, con.AccountId);
                accountIds.add(con.AccountId);
            }
        }
        Map<Id, Account> accountToUpdateMap = new Map<Id, Account>();
        for (Account acc : [SELECT Id, 	SLAExpirationDate__c FROM Account WHERE Id IN :accountIds]) {
            acc.SLAExpirationDate__c = Date.today();
            accountToUpdateMap.put(acc.Id, acc);
        }
        if (!accountToUpdateMap.isEmpty()) {
            update accountToUpdateMap.values();
        }
    }
}