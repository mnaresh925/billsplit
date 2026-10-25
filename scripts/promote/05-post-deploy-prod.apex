// Step 5 (anonymous Apex, run once in production after the deploy).
//   sf apex run -f scripts/promote/05-post-deploy-prod.apex -o <prod-alias>
// Schedules the nightly owner access sync and runs it once. Safe to rerun: it skips if the job exists.
String jobName = 'Bill Split nightly owner access sync';
Integer existing = [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :jobName];
if (existing == 0) {
    System.schedule(jobName, '0 0 2 * * ?', new OwnershipSharingBatch());
    System.debug('Scheduled: ' + jobName);
} else {
    System.debug('Already scheduled: ' + jobName);
}
Database.executeBatch(new OwnershipSharingBatch(), 100);
