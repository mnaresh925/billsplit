public with sharing class MeterTriggerHandler {

    public static void beforeSave(List<Meter__c> meters) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> unitIds = new Set<Id>();
        Set<Id> selfIds = new Set<Id>();
        for (Meter__c m : meters) {
            if (m.Utility_Account__c != null) {
                accountIds.add(m.Utility_Account__c);
            }
            if (m.Unit__c != null) {
                unitIds.add(m.Unit__c);
            }
            if (m.Id != null) {
                selfIds.add(m.Id);
            }
        }
        Map<Id, Utility_Account__c> accounts = new Map<Id, Utility_Account__c>([
            SELECT Id, Property__c FROM Utility_Account__c WHERE Id IN :accountIds
        ]);
        Map<Id, Unit__c> units = new Map<Id, Unit__c>([SELECT Id, Property__c FROM Unit__c WHERE Id IN :unitIds]);

        Set<String> takenKeys = new Set<String>();
        for (Meter__c e : [
            SELECT Utility_Account__c, Unit__c FROM Meter__c
            WHERE Utility_Account__c IN :accountIds AND Unit__c IN :unitIds
              AND Meter_Role__c = 'Sub' AND Active__c = true AND Id NOT IN :selfIds
        ]) {
            takenKeys.add(String.valueOf(e.Utility_Account__c) + '|' + String.valueOf(e.Unit__c));
        }

        for (Meter__c m : meters) {
            if (m.Unit__c != null) {
                Utility_Account__c ua = accounts.get(m.Utility_Account__c);
                Unit__c u = units.get(m.Unit__c);
                if (ua != null && u != null && ua.Property__c != u.Property__c) {
                    m.Unit__c.addError('The unit must belong to the same property as the utility account.');
                }
            }
            if (m.Meter_Role__c == 'Sub' && m.Active__c == true && m.Unit__c != null) {
                String key = String.valueOf(m.Utility_Account__c) + '|' + String.valueOf(m.Unit__c);
                if (!takenKeys.add(key)) {
                    m.Unit__c.addError('This unit already has an active sub-meter on this utility account.');
                }
            }
        }
    }
}