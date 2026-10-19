trigger TaskTrigger on Task (after insert, after update) {
    switch on Trigger.operationType {
        when AFTER_INSERT {
            TaskTriggerHelper.UpdateLastActivityDate(Trigger.new);
        }
    }
}