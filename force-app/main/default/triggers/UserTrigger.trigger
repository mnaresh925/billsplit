trigger UserTrigger on User (after insert, after update) {
    UserTriggerHandler.afterSave(Trigger.new);
}