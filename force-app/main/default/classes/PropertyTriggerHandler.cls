public with sharing class PropertyTriggerHandler {

    /** When a property address changes, re-save the units that share it so they pick up the new address. */
    public static void afterUpdate(List<Property__c> properties, Map<Id, Property__c> oldMap) {
        Set<Id> changed = new Set<Id>();
        for (Property__c p : properties) {
            Property__c o = oldMap.get(p.Id);
            if (o != null && addressChanged(p, o)) {
                changed.add(p.Id);
            }
        }
        if (changed.isEmpty()) {
            return;
        }
        List<Unit__c> units = [
            SELECT Id FROM Unit__c WHERE Property__c IN :changed AND Same_As_Property_Address__c = true
        ];
        if (!units.isEmpty()) {
            update units;
        }
    }

    private static Boolean addressChanged(Property__c n, Property__c o) {
        return n.Street__c != o.Street__c
            || n.Suburb__c != o.Suburb__c
            || n.State__c != o.State__c
            || n.Postcode__c != o.Postcode__c
            || n.Address_Source__c != o.Address_Source__c
            || n.Location__Latitude__s != o.Location__Latitude__s
            || n.Location__Longitude__s != o.Location__Longitude__s;
    }
}