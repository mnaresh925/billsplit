trigger PropertyTrigger on Property__c (after update) {
    PropertyTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
}