public with sharing class OwnershipTriggerHandler {

    public static void beforeSave(List<Ownership__c> rows) {
        Set<Id> unitIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (Ownership__c o : rows) {
            if (o.Unit__c != null) {
                unitIds.add(o.Unit__c);
            }
            if (o.Contact__c != null) {
                contactIds.add(o.Contact__c);
            }
        }
        Map<Id, Unit__c> units = new Map<Id, Unit__c>([SELECT Id, Property__c FROM Unit__c WHERE Id IN :unitIds]);
        Map<Id, Contact> contacts = new Map<Id, Contact>([
            SELECT Id, Name, Alternate_Billing_Email__c FROM Contact WHERE Id IN :contactIds
        ]);

        for (Ownership__c o : rows) {
            if (o.Unit__c != null) {
                Unit__c u = units.get(o.Unit__c);
                if (u != null && u.Property__c != o.Property__c) {
                    o.Unit__c.addError('The unit must belong to the same property as this ownership.');
                }
            }
            Boolean needsAlternate = o.Bill_Email_Preference__c == 'Alternate' || o.Bill_Email_Preference__c == 'Both';
            if (needsAlternate && o.Contact__c != null) {
                Contact c = contacts.get(o.Contact__c);
                if (c != null && String.isBlank(c.Alternate_Billing_Email__c)) {
                    o.Bill_Email_Preference__c.addError(c.Name
                        + ' has no Alternate Billing Email. Add one to the contact, or choose Primary.');
                }
            }
        }
    }

    // ------------------------------------------------------------------ Phase 5: owner portal sharing

    /** After insert, update and undelete: recompute portal access for the affected properties. */
    public static void afterSave(List<Ownership__c> rows) {
        Set<Id> propertyIds = new Set<Id>();
        for (Ownership__c o : rows) {
            if (o.Property__c != null) {
                propertyIds.add(o.Property__c);
            }
        }
        OwnershipSharingService.syncProperties(propertyIds);
    }

    /** After delete: remove portal access that no longer has an active ownership behind it. */
    public static void afterDelete(List<Ownership__c> rows) {
        afterSave(rows);
    }
}