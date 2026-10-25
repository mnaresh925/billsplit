trigger MeterReadingTrigger on Meter_Reading__c (before insert, before update, after insert, after update, after delete) {
    if (Trigger.isBefore) {
        MeterReadingTriggerHandler.beforeSave(Trigger.new);
    } else if (Trigger.isDelete) {
        MeterReadingTriggerHandler.afterDelete(Trigger.old);
    } else {
        MeterReadingTriggerHandler.afterChange(Trigger.new, Trigger.oldMap);
    }
}