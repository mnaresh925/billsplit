/**
 * When a portal user is created, activated or deactivated, queue a job that recomputes their property access.
 * The work runs in a separate transaction because User is a setup object and sharing rows are written by the job.
 */
public with sharing class UserTriggerHandler {

    public static void afterSave(List<User> users) {
        Set<Id> contactIds = new Set<Id>();
        for (User u : users) {
            if (u.ContactId != null) {
                contactIds.add(u.ContactId);
            }
        }
        if (!contactIds.isEmpty() && !System.isBatch() && !System.isFuture()) {
            System.enqueueJob(new OwnershipSharingService.ContactSyncJob(contactIds));
        }
    }
}