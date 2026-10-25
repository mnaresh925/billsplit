public with sharing class UnitTriggerHandler {

    public static void beforeInsert(List<Unit__c> units) {
        enforceUnitLimit(units);
        copyPropertyAddress(units);
    }

    public static void beforeUpdate(List<Unit__c> units) {
        copyPropertyAddress(units);
    }

    private static void enforceUnitLimit(List<Unit__c> units) {
        Set<Id> propertyIds = new Set<Id>();
        for (Unit__c u : units) {
            if (u.Property__c != null) {
                propertyIds.add(u.Property__c);
            }
        }
        if (propertyIds.isEmpty()) {
            return;
        }
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Property__c prop, COUNT(Id) total FROM Unit__c WHERE Property__c IN :propertyIds GROUP BY Property__c
        ]) {
            counts.put((Id) ar.get('prop'), (Integer) ar.get('total'));
        }
        Integer maxUnits = BillSplitSettings.maxUnitsPerProperty();
        for (Unit__c u : units) {
            if (u.Property__c == null) {
                continue;
            }
            Integer current = counts.containsKey(u.Property__c) ? counts.get(u.Property__c) : 0;
            if (current >= maxUnits) {
                u.addError('A property can have at most ' + maxUnits + ' units.');
            } else {
                counts.put(u.Property__c, current + 1);
            }
        }
    }

    private static void copyPropertyAddress(List<Unit__c> units) {
        Set<Id> propertyIds = new Set<Id>();
        for (Unit__c u : units) {
            if (u.Same_As_Property_Address__c == true && u.Property__c != null) {
                propertyIds.add(u.Property__c);
            }
        }
        if (propertyIds.isEmpty()) {
            return;
        }
        Map<Id, Property__c> properties = new Map<Id, Property__c>([
            SELECT Id, Street__c, Suburb__c, State__c, Postcode__c, Address_Source__c,
                   Location__Latitude__s, Location__Longitude__s
            FROM Property__c WHERE Id IN :propertyIds
        ]);
        for (Unit__c u : units) {
            if (u.Same_As_Property_Address__c != true) {
                continue;
            }
            Property__c p = properties.get(u.Property__c);
            if (p == null) {
                continue;
            }
            u.Street__c = p.Street__c;
            u.Suburb__c = p.Suburb__c;
            u.State__c = p.State__c;
            u.Postcode__c = p.Postcode__c;
            u.Address_Source__c = p.Address_Source__c;
            u.Location__Latitude__s = p.Location__Latitude__s;
            u.Location__Longitude__s = p.Location__Longitude__s;
        }
    }
}