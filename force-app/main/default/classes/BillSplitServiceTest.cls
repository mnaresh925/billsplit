@isTest
private class BillSplitServiceTest {

    private static void assertDec(Decimal expected, Decimal actual, String what) {
        System.assertNotEquals(null, actual, what + ' was null');
        System.assert((expected - actual).abs() < 0.0001, what + ': expected ' + expected + ' but was ' + actual);
    }

    private static Map<Id, Bill_Allocation__c> allocationsByUnit(Id billId) {
        Map<Id, Bill_Allocation__c> byUnit = new Map<Id, Bill_Allocation__c>();
        for (Bill_Allocation__c r : [
            SELECT Unit__c, Units_Consumed__c, Usage_Amount__c, Supply_Amount__c, Total_Amount__c,
                   Is_Residual__c, Unique_Key__c, Opening_Reading__c, Closing_Reading__c, Calculation_Notes__c
            FROM Bill_Allocation__c WHERE Utility_Bill__c = :billId
        ]) {
            byUnit.put(r.Unit__c, r);
        }
        return byUnit;
    }

    private static void assertFailsWith(Id billId, String fragment) {
        try {
            BillSplitService.calculateAndSave(billId);
            System.assert(false, 'Expected a BillSplitException containing "' + fragment + '".');
        } catch (BillSplitException e) {
            System.assert(e.getMessage().contains(fragment), 'Unexpected message: ' + e.getMessage());
        }
    }

    @isTest
    static void calculatesAndStoresTheWorkedExample() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();

        Test.startTest();
        BillSplitCalculator.SplitResult res = BillSplitService.calculateAndSave(s.bill.Id);
        Test.stopTest();

        System.assert(res.errors.isEmpty(), String.join(res.errors, ' '));
        Map<Id, Bill_Allocation__c> byUnit = allocationsByUnit(s.bill.Id);
        System.assertEquals(2, byUnit.size(), 'One allocation per unit');
        Bill_Allocation__c a = byUnit.get(s.unitA.Id);
        Bill_Allocation__c b = byUnit.get(s.unitB.Id);
        assertDec(317.00, a.Total_Amount__c, 'Unit A total');
        assertDec(163.00, b.Total_Amount__c, 'Unit B total');
        assertDec(82, a.Units_Consumed__c, 'Unit A units');
        assertDec(38, b.Units_Consumed__c, 'Unit B units');
        System.assertEquals(true, a.Is_Residual__c);
        System.assertEquals(false, b.Is_Residual__c);
        assertDec(1240, b.Opening_Reading__c, 'Opening reading');
        assertDec(1278, b.Closing_Reading__c, 'Closing reading');
        System.assertEquals(String.valueOf(s.bill.Id) + '|' + String.valueOf(s.unitB.Id), b.Unique_Key__c);
        System.assert(String.isNotBlank(b.Calculation_Notes__c));

        Utility_Bill__c bill = [
            SELECT Status__c, Calculated_At__c, Allocated_Amount__c, Allocation_Variance__c
            FROM Utility_Bill__c WHERE Id = :s.bill.Id
        ];
        System.assertEquals('Calculated', bill.Status__c);
        System.assertNotEquals(null, bill.Calculated_At__c);
        assertDec(480.00, bill.Allocated_Amount__c, 'Allocated amount');
        assertDec(0, bill.Allocation_Variance__c, 'Variance');
    }

    @isTest
    static void recalculatingReplacesTheAllocationsInsteadOfDuplicatingThem() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitService.calculateAndSave(s.bill.Id);
        BillSplitService.calculateAndSave(s.bill.Id);
        System.assertEquals(2, allocationsByUnit(s.bill.Id).size());
    }

    @isTest
    static void previewDoesNotWriteAnything() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitCalculator.SplitResult res = BillSplitService.preview(s.bill.Id);
        System.assert(res.errors.isEmpty(), String.join(res.errors, ' '));
        assertDec(163.00, res.units[1].totalAmount, 'Unit B total');
        System.assertEquals(0, allocationsByUnit(s.bill.Id).size());
        System.assertEquals('Draft', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :s.bill.Id].Status__c);
    }

    @isTest
    static void missingClosingReadingStopsTheCalculation() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        delete s.closing;
        assertFailsWith(s.bill.Id, 'closing reading');
        System.assertEquals(0, allocationsByUnit(s.bill.Id).size());
    }

    @isTest
    static void missingBaselineStopsTheCalculation() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        delete s.baseline;
        assertFailsWith(s.bill.Id, 'opening reading');
    }

    @isTest
    static void openingReadingIsThePreviousBillsClosingReading() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        // A second bill for the next quarter: the opening reading must be this bill's closing reading (1278).
        Date start2 = s.bill.Period_End__c.addDays(1);
        Date end2 = start2.addDays(89);
        Utility_Bill__c bill2 = BillSplitTestData.billRecord(s.account.Id, 'BILL-2', start2, end2, 100, 300.00, null);
        insert bill2;
        insert BillSplitTestData.readingRecord(s.meter.Id, 'Bill Close', end2.addDays(-1), 1300, bill2.Id);
        BillSplitCalculator.SplitResult res = BillSplitService.preview(bill2.Id);
        System.assert(res.errors.isEmpty(), String.join(res.errors, ' '));
        assertDec(1278, res.units[1].openingReading, 'Opening reading');
        assertDec(22, res.units[1].unitsConsumed, 'Sub-meter units');
    }

    @isTest
    static void equalMethodDoesNotNeedAMeter() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        update new Utility_Bill__c(Id = s.bill.Id, Split_Method__c = 'Equal');
        BillSplitService.calculateAndSave(s.bill.Id);
        Map<Id, Bill_Allocation__c> byUnit = allocationsByUnit(s.bill.Id);
        assertDec(240.00, byUnit.get(s.unitA.Id).Total_Amount__c, 'Unit A total');
        assertDec(240.00, byUnit.get(s.unitB.Id).Total_Amount__c, 'Unit B total');
    }

    @isTest
    static void aPropertyWithoutTwoUnitsCannotBeSplit() {
        Property__c p = BillSplitTestData.property('1 Lone St');
        BillSplitTestData.unit(p.Id, 'Only Unit');
        Utility_Account__c ua = BillSplitTestData.waterAccount(p.Id, 'ACC-LONE');
        Date periodEnd = Date.today().addDays(-1);
        Utility_Bill__c bill = BillSplitTestData.billRecord(ua.Id, 'BILL-L', periodEnd.addDays(-90), periodEnd, 100, 300.00, null);
        insert bill;
        assertFailsWith(bill.Id, 'exactly 2 units');
    }

    @isTest
    static void aSentBillNeedsThePermissionToReopen() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitService.calculateAndSave(s.bill.Id);
        update new Utility_Bill__c(Id = s.bill.Id, Status__c = 'Sent');

        BillSplitService.reopenPermissionOverride = false;
        assertFailsWith(s.bill.Id, 'has been sent');

        BillSplitService.reopenPermissionOverride = true;
        BillSplitService.calculateAndSave(s.bill.Id);
        System.assertEquals('Calculated', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :s.bill.Id].Status__c);
    }

    @isTest
    static void sentBillFiguresAreLockedByTheValidationRule() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitService.calculateAndSave(s.bill.Id);
        update new Utility_Bill__c(Id = s.bill.Id, Status__c = 'Sent');
        Database.SaveResult sr = Database.update(new Utility_Bill__c(Id = s.bill.Id, Total_Amount__c = 999.00), false);
        System.assert(!sr.isSuccess(), 'Changing figures on a sent bill should be blocked.');
        System.assert(sr.getErrors()[0].getMessage().contains('has been sent'), sr.getErrors()[0].getMessage());
    }
}