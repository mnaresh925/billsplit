@isTest
private class BillSplitControllerTest {

    private static void assertDec(Decimal expected, Decimal actual, String what) {
        System.assertNotEquals(null, actual, what + ' was null');
        System.assert((expected - actual).abs() < 0.0001, what + ': expected ' + expected + ' but was ' + actual);
    }

    private static Map<String, BillSplitController.AllocationRow> byUnit(BillSplitController.WorkbenchData d) {
        Map<String, BillSplitController.AllocationRow> m = new Map<String, BillSplitController.AllocationRow>();
        for (BillSplitController.AllocationRow r : d.allocations) {
            m.put(r.unitName, r);
        }
        return m;
    }

    @isTest
    static void getWorkbenchReturnsBillMeterAndReadings() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();

        BillSplitController.WorkbenchData d = BillSplitController.getWorkbench(s.bill.Id);

        System.assertEquals('BILL-1', d.billNumber);
        System.assertEquals('Draft', d.status);
        System.assertEquals('Water', d.utilityType);
        System.assertEquals('kL', d.unitOfMeasure);
        System.assertEquals(s.property.Id, d.propertyId);
        assertDec(480.00, d.totalAmount, 'Total amount');
        System.assertNotEquals(null, d.meter, 'Sub-meter details');
        System.assertEquals('SUB-1', d.meter.meterName);
        System.assertEquals('Unit B', d.meter.unitName);
        assertDec(1240, d.meter.openingValue, 'Opening reading');
        assertDec(1278, d.meter.closingValue, 'Closing reading');
        System.assertEquals(false, d.needsClosingReading);
        System.assertEquals(true, d.canCalculate);
        System.assertEquals(0, d.allocations.size(), 'Nothing calculated yet');
    }

    @isTest
    static void calculateStoresTheSplitAndReturnsRows() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();

        BillSplitController.WorkbenchData d = BillSplitController.calculate(s.bill.Id);

        System.assertEquals('Calculated', d.status);
        System.assertEquals(2, d.allocations.size());
        Map<String, BillSplitController.AllocationRow> rows = byUnit(d);
        assertDec(317.00, rows.get('Unit A').totalAmount, 'Unit A total');
        assertDec(163.00, rows.get('Unit B').totalAmount, 'Unit B total');
        System.assertEquals(true, rows.get('Unit A').isResidual);
        assertDec(0, d.variance, 'Variance');
    }

    @isTest
    static void calculateBlocksWhenClosingReadingIsMissing() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        delete s.closing;

        BillSplitController.WorkbenchData d = BillSplitController.getWorkbench(s.bill.Id);
        System.assertEquals(true, d.needsClosingReading);
        System.assertEquals(false, d.canCalculate);

        try {
            BillSplitController.calculate(s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
            System.assertNotEquals('Script-thrown exception', e.getMessage());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Bill_Allocation__c WHERE Utility_Bill__c = :s.bill.Id]);
    }

    @isTest
    static void saveClosingReadingCreatesThenUpdates() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        delete s.closing;
        Date closeDate = s.bill.Period_End__c;

        BillSplitController.WorkbenchData d = BillSplitController.saveClosingReading(s.bill.Id, 1278, closeDate);
        System.assertEquals(false, d.needsClosingReading);
        assertDec(1278, d.meter.closingValue, 'Created closing reading');
        System.assertEquals(1, [SELECT COUNT() FROM Meter_Reading__c WHERE Utility_Bill__c = :s.bill.Id]);

        d = BillSplitController.saveClosingReading(s.bill.Id, 1280, closeDate);
        assertDec(1280, d.meter.closingValue, 'Updated closing reading');
        System.assertEquals(1, [SELECT COUNT() FROM Meter_Reading__c WHERE Utility_Bill__c = :s.bill.Id],
            'Updating must not add a second closing reading');
    }

    @isTest
    static void changingTheReadingSendsACalculatedBillBackToDraft() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitController.calculate(s.bill.Id);

        BillSplitController.WorkbenchData d = BillSplitController.saveClosingReading(s.bill.Id, 1280, s.closing.Reading_Date__c);

        System.assertEquals('Draft', d.status);
    }

    @isTest
    static void readingBelowTheOpeningReadingIsRejectedWithAReadableMessage() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        delete s.closing;

        try {
            BillSplitController.saveClosingReading(s.bill.Id, 1000, s.bill.Period_End__c);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('lower'), 'Unexpected message: ' + e.getMessage());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Meter_Reading__c WHERE Utility_Bill__c = :s.bill.Id]);
    }

    @isTest
    static void saveClosingReadingRequiresValueAndDate() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        try {
            BillSplitController.saveClosingReading(s.bill.Id, null, null);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Enter the closing reading'));
        }
    }

    @isTest
    static void sentBillIsLockedWithoutTheReopenPermission() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitController.calculate(s.bill.Id);
        update new Utility_Bill__c(Id = s.bill.Id, Status__c = 'Sent', Sent_At__c = System.now());
        BillSplitController.reopenPermissionOverride = false;

        BillSplitController.WorkbenchData d = BillSplitController.getWorkbench(s.bill.Id);
        System.assertEquals(true, d.isLocked);
        System.assertEquals(false, d.canCalculate);
        System.assertEquals(false, d.canEditReading);

        try {
            BillSplitController.saveClosingReading(s.bill.Id, 1280, s.closing.Reading_Date__c);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('sent'), 'Unexpected message: ' + e.getMessage());
        }

        BillSplitController.reopenPermissionOverride = true;
        d = BillSplitController.getWorkbench(s.bill.Id);
        System.assertEquals(false, d.isLocked);
    }

    @isTest
    static void canSendFollowsStatusAndPermission() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitController.sendPermissionOverride = true;
        System.assertEquals(false, BillSplitController.getWorkbench(s.bill.Id).canSend, 'Draft bills cannot be sent');

        BillSplitController.calculate(s.bill.Id);
        System.assertEquals(true, BillSplitController.getWorkbench(s.bill.Id).canSend);

        BillSplitController.sendPermissionOverride = false;
        System.assertEquals(false, BillSplitController.getWorkbench(s.bill.Id).canSend);
    }

    @isTest
    static void unknownBillGivesAReadableError() {
        try {
            BillSplitController.getWorkbench(null);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assertEquals('A bill is required.', e.getMessage());
        }
    }
}