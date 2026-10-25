/**
 * Works out which properties and units the logged in portal user owns. Runs without sharing because portal
 * users cannot read Ownership or User records directly. It only ever returns the current user's own rows,
 * keyed on the user's Contact, never on anything sent from the browser.
 */
public without sharing class OwnerPortalAccess {

    /** Test seam: pretend the current user is this contact. */
    @TestVisible private static Id contactIdOverride;

    public Id contactId;
    /** Property -> the units this contact owns there. Empty set with wholeProperty = true means every unit. */
    public Map<Id, Set<Id>> unitsByProperty = new Map<Id, Set<Id>>();
    public Set<Id> wholeProperty = new Set<Id>();
    public Map<Id, String> roleByProperty = new Map<Id, String>();

    public static OwnerPortalAccess forCurrentUser() {
        OwnerPortalAccess a = new OwnerPortalAccess();
        a.contactId = currentContactId();
        if (a.contactId == null) {
            return a;
        }
        for (Ownership__c o : [
            SELECT Property__c, Unit__c, Role__c FROM Ownership__c
            WHERE Contact__c = :a.contactId AND Is_Active__c = true
        ]) {
            if (!a.unitsByProperty.containsKey(o.Property__c)) {
                a.unitsByProperty.put(o.Property__c, new Set<Id>());
                a.roleByProperty.put(o.Property__c, o.Role__c);
            }
            if (o.Unit__c == null) {
                a.wholeProperty.add(o.Property__c);
            } else {
                a.unitsByProperty.get(o.Property__c).add(o.Unit__c);
            }
        }
        return a;
    }

    public Boolean hasProperty(Id propertyId) {
        return propertyId != null && unitsByProperty.containsKey(propertyId);
    }

    public Boolean ownsUnit(Id propertyId, Id unitId) {
        return wholeProperty.contains(propertyId)
            || (unitsByProperty.containsKey(propertyId) && unitsByProperty.get(propertyId).contains(unitId));
    }

    private static Id currentContactId() {
        if (contactIdOverride != null) {
            return contactIdOverride;
        }
        List<User> users = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId()];
        return users.isEmpty() ? null : users[0].ContactId;
    }
}