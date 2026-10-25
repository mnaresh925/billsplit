public with sharing class MeterReadingTriggerHandler {

    private static final String TYPE_BASELINE = 'Baseline';
    private static final String TYPE_BILL_CLOSE = 'Bill Close';

    public static void beforeSave(List<Meter_Reading__c> rows) {
        Set<Id> meterIds = new Set<Id>();
        Set<Id> billIds = new Set<Id>();
        Set<Id> selfIds = new Set<Id>();
        for (Meter_Reading__c r : rows) {
            if (r.Meter__c != null) {
                meterIds.add(r.Meter__c);
            }
            if (r.Utility_Bill__c != null) {
                billIds.add(r.Utility_Bill__c);
            }
            if (r.Id != null) {
                selfIds.add(r.Id);
            }
        }
        Map<Id, Meter__c> meters = new Map<Id, Meter__c>([
            SELECT Id, Utility_Account__c FROM Meter__c WHERE Id IN :meterIds
        ]);
        Map<Id, Utility_Bill__c> bills = new Map<Id, Utility_Bill__c>([
            SELECT Id, Utility_Account__c FROM Utility_Bill__c WHERE Id IN :billIds
        ]);
        Map<Id, List<Meter_Reading__c>> existingByMeter = new Map<Id, List<Meter_Reading__c>>();
        for (Meter_Reading__c e : [
            SELECT Id, Meter__c, Reading_Date__c, Reading_Value__c, Reading_Type__c, Utility_Bill__c
            FROM Meter_Reading__c WHERE Meter__c IN :meterIds AND Id NOT IN :selfIds
        ]) {
            if (!existingByMeter.containsKey(e.Meter__c)) {
                existingByMeter.put(e.Meter__c, new List<Meter_Reading__c>());
            }
            existingByMeter.get(e.Meter__c).add(e);
        }

        for (Integer i = 0; i < rows.size(); i++) {
            Meter_Reading__c r = rows[i];
            if (r.Meter__c == null) {
                continue;
            }
            if (r.Utility_Bill__c != null) {
                Utility_Bill__c b = bills.get(r.Utility_Bill__c);
                Meter__c m = meters.get(r.Meter__c);
                if (b != null && m != null && b.Utility_Account__c != m.Utility_Account__c) {
                    r.Utility_Bill__c.addError('The bill must belong to the same utility account as the meter.');
                }
            }
            List<Meter_Reading__c> others = new List<Meter_Reading__c>();
            if (existingByMeter.containsKey(r.Meter__c)) {
                others.addAll(existingByMeter.get(r.Meter__c));
            }
            for (Integer j = 0; j < rows.size(); j++) {
                if (j != i && rows[j].Meter__c == r.Meter__c) {
                    others.add(rows[j]);
                }
            }
            checkAgainstOthers(r, others);
        }
    }

    private static void checkAgainstOthers(Meter_Reading__c r, List<Meter_Reading__c> others) {
        for (Meter_Reading__c o : others) {
            if (r.Reading_Type__c == TYPE_BASELINE && o.Reading_Type__c == TYPE_BASELINE) {
                r.Reading_Type__c.addError('This meter already has a baseline reading.');
            }
            if (r.Reading_Type__c == TYPE_BILL_CLOSE && o.Reading_Type__c == TYPE_BILL_CLOSE
                && r.Utility_Bill__c != null && r.Utility_Bill__c == o.Utility_Bill__c) {
                r.Utility_Bill__c.addError('This meter already has a closing reading for this bill.');
            }
            if (r.Reading_Date__c == null || r.Reading_Value__c == null
                || o.Reading_Date__c == null || o.Reading_Value__c == null) {
                continue;
            }
            if (o.Reading_Date__c < r.Reading_Date__c && o.Reading_Value__c > r.Reading_Value__c) {
                r.Reading_Value__c.addError('The reading ' + r.Reading_Value__c + ' is lower than the earlier reading '
                    + o.Reading_Value__c + ' taken on ' + o.Reading_Date__c.format() + '.');
            } else if (o.Reading_Date__c > r.Reading_Date__c && o.Reading_Value__c < r.Reading_Value__c) {
                r.Reading_Value__c.addError('The reading ' + r.Reading_Value__c + ' is higher than the later reading '
                    + o.Reading_Value__c + ' taken on ' + o.Reading_Date__c.format() + '.');
            }
        }
    }

    // A changed reading makes a calculated split out of date, so send the bill back to Draft.

    public static void afterChange(List<Meter_Reading__c> rows, Map<Id, Meter_Reading__c> oldMap) {
        Set<Id> billIds = new Set<Id>();
        for (Meter_Reading__c r : rows) {
            if (r.Utility_Bill__c != null) {
                billIds.add(r.Utility_Bill__c);
            }
            if (oldMap != null && oldMap.containsKey(r.Id) && oldMap.get(r.Id).Utility_Bill__c != null) {
                billIds.add(oldMap.get(r.Id).Utility_Bill__c);
            }
        }
        markBillsStale(billIds);
    }

    public static void afterDelete(List<Meter_Reading__c> rows) {
        Set<Id> billIds = new Set<Id>();
        for (Meter_Reading__c r : rows) {
            if (r.Utility_Bill__c != null) {
                billIds.add(r.Utility_Bill__c);
            }
        }
        markBillsStale(billIds);
    }

    private static void markBillsStale(Set<Id> billIds) {
        if (billIds.isEmpty()) {
            return;
        }
        List<Utility_Bill__c> stale = [
            SELECT Id FROM Utility_Bill__c WHERE Id IN :billIds AND Status__c = 'Calculated'
        ];
        for (Utility_Bill__c b : stale) {
            b.Status__c = 'Draft';
            b.Calculated_At__c = null;
        }
        if (!stale.isEmpty()) {
            update stale;
        }
    }
}