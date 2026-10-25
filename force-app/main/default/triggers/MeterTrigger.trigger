trigger MeterTrigger on Meter__c (before insert, before update) {
    MeterTriggerHandler.beforeSave(Trigger.new);
}