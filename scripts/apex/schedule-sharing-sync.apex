// Schedules the nightly owner access sync at 2:00 AM. Run once per org:
//   sf apex run -f scripts/apex/schedule-sharing-sync.apex -o billsplit
System.schedule('Bill Split nightly owner access sync', '0 0 2 * * ?', new OwnershipSharingBatch());

// Run it once now to bring existing owners in line (for example the demo data):
Database.executeBatch(new OwnershipSharingBatch(), 100);
