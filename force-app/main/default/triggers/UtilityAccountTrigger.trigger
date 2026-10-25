trigger UtilityAccountTrigger on Utility_Account__c (before insert, before update) {
    UtilityAccountTriggerHandler.beforeSave(Trigger.new);
}