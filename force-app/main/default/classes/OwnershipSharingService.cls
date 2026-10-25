/**
 * Keeps Property__Share rows (sharing reason Owner_Access) in line with ownerships.
 *
 * Rule: a portal user can read a property exactly while their contact has an active ownership on it.
 * "Active" is the Ownership__c.Is_Active__c formula (started, and not past its end date).
 *
 * Runs without sharing because it writes share rows. Nothing here is callable from the UI. The rule is
 * recomputed from the data each time, so it can run repeatedly (triggers, the user job and the nightly batch)
 * and always converges on the same result. Child records (units, accounts, bills, allocations) inherit access
 * from the property because they are master-detail children.
 */
public without sharing class OwnershipSharingService {

    private static String reason() {
        return Schema.Property__Share.RowCause.Owner_Access__c;
    }

    /** Recomputes access for the given properties. Errors are logged, never thrown, so staff saves are not blocked. */
    public static void syncProperties(Set<Id> propertyIds) {
        if (propertyIds == null || propertyIds.isEmpty()) {
            return;
        }
        Set<String> desired = desiredKeys(propertyIds);

        List<Property__Share> existing = [
            SELECT Id, ParentId, UserOrGroupId FROM Property__Share
            WHERE ParentId IN :propertyIds AND RowCause = :reason()
        ];
        Set<String> present = new Set<String>();
        List<Property__Share> toDelete = new List<Property__Share>();
        for (Property__Share s : existing) {
            String key = key(s.ParentId, s.UserOrGroupId);
            if (desired.contains(key) && present.add(key)) {
                continue;
            }
            toDelete.add(s);
        }

        List<Property__Share> toAdd = new List<Property__Share>();
        for (String key : desired) {
            if (!present.contains(key)) {
                String[] parts = key.split('\\|');
                toAdd.add(new Property__Share(
                    ParentId = parts[0], UserOrGroupId = parts[1], AccessLevel = 'Read', RowCause = reason()
                ));
            }
        }
        logInsert(Database.insert(toAdd, false));
        if (!toDelete.isEmpty()) {
            logDelete(Database.delete(toDelete, false));
        }
    }

    /** Recomputes access for every property any of these contacts has (or had) an ownership on. */
    public static void syncContacts(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return;
        }
        Set<Id> propertyIds = new Set<Id>();
        for (Ownership__c o : [SELECT Property__c FROM Ownership__c WHERE Contact__c IN :contactIds]) {
            propertyIds.add(o.Property__c);
        }
        // Also revisit properties where these users already hold a share, so a removed ownership is cleaned up.
        Set<Id> userIds = new Map<Id, User>([SELECT Id FROM User WHERE ContactId IN :contactIds]).keySet();
        if (!userIds.isEmpty()) {
            for (Property__Share s : [
                SELECT ParentId FROM Property__Share WHERE UserOrGroupId IN :userIds AND RowCause = :reason()
            ]) {
                propertyIds.add(s.ParentId);
            }
        }
        syncProperties(propertyIds);
    }

    /** Queued when a portal user is created, activated or deactivated. */
    public class ContactSyncJob implements Queueable {
        private Set<Id> contactIds;

        public ContactSyncJob(Set<Id> contactIds) {
            this.contactIds = contactIds;
        }

        public void execute(QueueableContext context) {
            OwnershipSharingService.syncContacts(contactIds);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static Set<String> desiredKeys(Set<Id> propertyIds) {
        List<Ownership__c> active = [
            SELECT Property__c, Contact__c FROM Ownership__c
            WHERE Property__c IN :propertyIds AND Is_Active__c = true
        ];
        Set<Id> contactIds = new Set<Id>();
        for (Ownership__c o : active) {
            contactIds.add(o.Contact__c);
        }
        Map<Id, List<Id>> usersByContact = new Map<Id, List<Id>>();
        if (!contactIds.isEmpty()) {
            for (User u : [SELECT Id, ContactId FROM User WHERE ContactId IN :contactIds AND IsActive = true]) {
                if (!usersByContact.containsKey(u.ContactId)) {
                    usersByContact.put(u.ContactId, new List<Id>());
                }
                usersByContact.get(u.ContactId).add(u.Id);
            }
        }
        Set<String> keys = new Set<String>();
        for (Ownership__c o : active) {
            List<Id> users = usersByContact.get(o.Contact__c);
            if (users != null) {
                for (Id userId : users) {
                    keys.add(key(o.Property__c, userId));
                }
            }
        }
        return keys;
    }

    private static String key(Id propertyId, Id userId) {
        return String.valueOf(propertyId) + '|' + String.valueOf(userId);
    }

    private static void logInsert(List<Database.SaveResult> results) {
        for (Database.SaveResult r : results) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Owner access share could not be added: ' + r.getErrors());
            }
        }
    }

    private static void logDelete(List<Database.DeleteResult> results) {
        for (Database.DeleteResult r : results) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Owner access share could not be removed: ' + r.getErrors());
            }
        }
    }
}