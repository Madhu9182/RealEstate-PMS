trigger PropertyTrigger on Property__c(before insert, before update, after insert, after update) {
    PropertyTriggerHandler.run(Trigger.operationType, Trigger.new, Trigger.oldMap);
}