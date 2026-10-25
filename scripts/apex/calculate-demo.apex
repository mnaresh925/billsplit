// Calculates and stores the split for the demo bill created by seed-data.apex, then prints the result.
// Run:  sf apex run -f scripts/apex/calculate-demo.apex -o <alias>
Utility_Bill__c bill = [
    SELECT Id FROM Utility_Bill__c WHERE Bill_Number__c = 'DEMO-0001' ORDER BY CreatedDate DESC LIMIT 1
];
BillSplitCalculator.SplitResult res = BillSplitService.calculateAndSave(bill.Id);

for (BillSplitCalculator.UnitResult u : res.units) {
    System.debug('SPLIT ' + u.label + ': units ' + u.unitsConsumed + ', usage ' + u.usageAmount
        + ', supply ' + u.supplyAmount + ', total ' + u.totalAmount + (u.isResidual ? ' (residual)' : ' (sub-metered)'));
}
for (String w : res.warnings) {
    System.debug('WARNING ' + w);
}
System.debug('NOTES' + '\n' + res.notes);

Utility_Bill__c after = [
    SELECT Status__c, Total_Amount__c, Allocated_Amount__c, Allocation_Variance__c FROM Utility_Bill__c WHERE Id = :bill.Id
];
System.debug('BILL ' + after.Status__c + ', total ' + after.Total_Amount__c + ', allocated ' + after.Allocated_Amount__c
    + ', variance ' + after.Allocation_Variance__c);
