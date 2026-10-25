trigger UnitTrigger on Unit__c (before insert, before update) {
    if (Trigger.isInsert) {
        UnitTriggerHandler.beforeInsert(Trigger.new);
    } else {
        UnitTriggerHandler.beforeUpdate(Trigger.new);
    }
}