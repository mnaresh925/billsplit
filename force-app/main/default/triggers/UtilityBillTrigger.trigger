trigger UtilityBillTrigger on Utility_Bill__c (before insert, before update) {
    if (Trigger.isInsert) {
        UtilityBillTriggerHandler.beforeInsert(Trigger.new);
    } else {
        UtilityBillTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}