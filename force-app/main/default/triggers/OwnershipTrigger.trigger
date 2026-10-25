trigger OwnershipTrigger on Ownership__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        OwnershipTriggerHandler.beforeSave(Trigger.new);
    } else if (Trigger.isDelete) {
        OwnershipTriggerHandler.afterDelete(Trigger.old);
    } else {
        OwnershipTriggerHandler.afterSave(Trigger.new);
    }
}