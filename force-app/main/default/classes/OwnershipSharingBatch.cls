/**
 * Nightly safety net. Ownerships end by date, which changes Is_Active__c without any save, so no trigger fires.
 * This job recomputes access for every property. Schedule it with scripts/apex/schedule-sharing-sync.apex.
 */
public with sharing class OwnershipSharingBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Property__c');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        OwnershipSharingService.syncProperties(new Map<Id, SObject>(scope).keySet());
    }

    public void finish(Database.BatchableContext bc) {
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new OwnershipSharingBatch(), 100);
    }
}