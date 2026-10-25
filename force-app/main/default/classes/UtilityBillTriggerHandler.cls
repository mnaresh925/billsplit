public with sharing class UtilityBillTriggerHandler {

    public static void beforeInsert(List<Utility_Bill__c> bills) {
        prepare(bills);
    }

    public static void beforeUpdate(List<Utility_Bill__c> bills, Map<Id, Utility_Bill__c> oldMap) {
        prepare(bills);
        resetStaleSplits(bills, oldMap);
    }

    private static void prepare(List<Utility_Bill__c> bills) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> selfIds = new Set<Id>();
        for (Utility_Bill__c b : bills) {
            if (String.isBlank(b.Status__c)) {
                b.Status__c = 'Draft';
            }
            if (b.Utility_Account__c != null) {
                accountIds.add(b.Utility_Account__c);
                if (String.isNotBlank(b.Bill_Number__c)) {
                    b.Bill_Number__c = b.Bill_Number__c.trim();
                    b.Unique_Key__c = String.valueOf(b.Utility_Account__c) + '|' + b.Bill_Number__c;
                }
            }
            if (b.Id != null) {
                selfIds.add(b.Id);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }
        List<Utility_Bill__c> existing = [
            SELECT Id, Bill_Number__c, Utility_Account__c, Period_Start__c, Period_End__c
            FROM Utility_Bill__c WHERE Utility_Account__c IN :accountIds AND Id NOT IN :selfIds
        ];
        for (Integer i = 0; i < bills.size(); i++) {
            Utility_Bill__c b = bills[i];
            if (b.Period_Start__c == null || b.Period_End__c == null) {
                continue;
            }
            for (Utility_Bill__c o : existing) {
                if (o.Utility_Account__c == b.Utility_Account__c && overlaps(b, o)) {
                    b.Period_Start__c.addError('This billing period overlaps bill ' + o.Bill_Number__c + '.');
                }
            }
            for (Integer j = 0; j < bills.size(); j++) {
                if (j != i && bills[j].Utility_Account__c == b.Utility_Account__c && overlaps(b, bills[j])) {
                    b.Period_Start__c.addError('This billing period overlaps another bill in the same save.');
                }
            }
        }
    }

    private static Boolean overlaps(Utility_Bill__c a, Utility_Bill__c b) {
        if (b.Period_Start__c == null || b.Period_End__c == null) {
            return false;
        }
        return a.Period_Start__c <= b.Period_End__c && a.Period_End__c >= b.Period_Start__c;
    }

    // Changing the figures after a split was calculated makes the stored split out of date.
    private static void resetStaleSplits(List<Utility_Bill__c> bills, Map<Id, Utility_Bill__c> oldMap) {
        for (Utility_Bill__c b : bills) {
            Utility_Bill__c o = oldMap.get(b.Id);
            if (o == null || o.Status__c != 'Calculated' || b.Status__c != 'Calculated') {
                continue;
            }
            Boolean changed = b.Total_Amount__c != o.Total_Amount__c
                || b.Total_Units_Consumed__c != o.Total_Units_Consumed__c
                || b.Supply_Charge__c != o.Supply_Charge__c
                || b.Split_Method__c != o.Split_Method__c
                || b.Period_Start__c != o.Period_Start__c
                || b.Period_End__c != o.Period_End__c;
            if (changed) {
                b.Status__c = 'Draft';
                b.Calculated_At__c = null;
            }
        }
    }
}