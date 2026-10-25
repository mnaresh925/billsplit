@isTest
private class BillSplitTriggerTest {

    private static void assertBlocked(Database.SaveResult sr, String fragment) {
        System.assert(!sr.isSuccess(), 'Expected the save to be blocked with "' + fragment + '".');
        String all = '';
        for (Database.Error err : sr.getErrors()) {
            all += err.getMessage() + ' | ';
        }
        System.assert(all.contains(fragment), 'Expected "' + fragment + '" but got: ' + all);
    }

    // ---------------------------------------------------------------- units

    @isTest
    static void aThirdUnitIsBlocked() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Database.SaveResult sr = Database.insert(BillSplitTestData.unitRecord(s.property.Id, 'Unit C'), false);
        assertBlocked(sr, 'at most 2 units');
    }

    @isTest
    static void theUnitLimitComesFromSettings() {
        BillSplitSettings.maxUnitsOverride = 3;
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Database.SaveResult sr = Database.insert(BillSplitTestData.unitRecord(s.property.Id, 'Unit C'), false);
        System.assert(sr.isSuccess(), 'A third unit is allowed when the limit is 3.');
    }

    @isTest
    static void bulkInsertRespectsTheLimitWithinOneBatch() {
        Property__c p = BillSplitTestData.property('5 Batch St');
        List<Unit__c> batch = new List<Unit__c>{
            BillSplitTestData.unitRecord(p.Id, 'Unit 1'),
            BillSplitTestData.unitRecord(p.Id, 'Unit 2'),
            BillSplitTestData.unitRecord(p.Id, 'Unit 3')
        };
        List<Database.SaveResult> results = Database.insert(batch, false);
        System.assert(results[0].isSuccess());
        System.assert(results[1].isSuccess());
        assertBlocked(results[2], 'at most 2 units');
    }

    @isTest
    static void aUnitCanShareThePropertyAddress() {
        Property__c p = BillSplitTestData.property('7 Shared St');
        Unit__c u = new Unit__c(Name = 'Unit 1', Property__c = p.Id, Same_As_Property_Address__c = true,
                                Address_Source__c = 'Manual', Status__c = 'Occupied');
        insert u;
        Unit__c saved = [SELECT Street__c, Suburb__c, State__c, Postcode__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('7 Shared St', saved.Street__c);
        System.assertEquals('Turner', saved.Suburb__c);
        System.assertEquals('ACT', saved.State__c);
        System.assertEquals('2612', saved.Postcode__c);
    }

    @isTest
    static void changingThePropertyAddressUpdatesSharedUnits() {
        Property__c p = BillSplitTestData.property('9 Old St');
        Unit__c shared = new Unit__c(Name = 'Unit 1', Property__c = p.Id, Same_As_Property_Address__c = true,
                                     Address_Source__c = 'Manual', Status__c = 'Occupied');
        Unit__c own = BillSplitTestData.unitRecord(p.Id, 'Unit 2');
        insert new List<Unit__c>{ shared, own };

        p.Street__c = '9 New St';
        update p;

        System.assertEquals('9 New St', [SELECT Street__c FROM Unit__c WHERE Id = :shared.Id].Street__c);
        System.assertEquals('Unit 2 Street', [SELECT Street__c FROM Unit__c WHERE Id = :own.Id].Street__c);
    }

    // ---------------------------------------------------------------- ownership

    @isTest
    static void alternatePreferenceNeedsAnAlternateEmail() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Contact noAlt = BillSplitTestData.contact('NoAlt', 'noalt@example.com', null);
        Contact withAlt = BillSplitTestData.contact('WithAlt', 'withalt@example.com', 'billing@example.com');

        assertBlocked(Database.insert(BillSplitTestData.ownershipRecord(s.property.Id, noAlt.Id, s.unitA.Id, 'Alternate'), false),
            'no Alternate Billing Email');
        assertBlocked(Database.insert(BillSplitTestData.ownershipRecord(s.property.Id, noAlt.Id, s.unitA.Id, 'Both'), false),
            'no Alternate Billing Email');
        System.assert(Database.insert(BillSplitTestData.ownershipRecord(s.property.Id, noAlt.Id, s.unitA.Id, 'Primary'), false).isSuccess());
        System.assert(Database.insert(BillSplitTestData.ownershipRecord(s.property.Id, withAlt.Id, s.unitB.Id, 'Both'), false).isSuccess());
    }

    @isTest
    static void anOwnershipUnitMustBelongToTheSameProperty() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Property__c other = BillSplitTestData.property('99 Other St');
        Unit__c otherUnit = BillSplitTestData.unit(other.Id, 'Other Unit');
        Contact c = BillSplitTestData.contact('Owner', 'owner@example.com', null);
        assertBlocked(Database.insert(BillSplitTestData.ownershipRecord(s.property.Id, c.Id, otherUnit.Id, 'Primary'), false),
            'same property');
    }

    // ---------------------------------------------------------------- meters

    @isTest
    static void aUnitCanOnlyHaveOneActiveSubMeterPerAccount() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Database.SaveResult second = Database.insert(BillSplitTestData.meterRecord(s.account.Id, s.unitB.Id, 'SUB-2'), false);
        assertBlocked(second, 'already has an active sub-meter');

        Meter__c inactive = BillSplitTestData.meterRecord(s.account.Id, s.unitB.Id, 'SUB-3');
        inactive.Active__c = false;
        System.assert(Database.insert(inactive, false).isSuccess(), 'An inactive meter is allowed.');
    }

    @isTest
    static void aSubMeterUnitMustBelongToTheAccountsProperty() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Property__c other = BillSplitTestData.property('98 Other St');
        Unit__c otherUnit = BillSplitTestData.unit(other.Id, 'Other Unit');
        assertBlocked(Database.insert(BillSplitTestData.meterRecord(s.account.Id, otherUnit.Id, 'SUB-X'), false),
            'same property');
    }

    // ---------------------------------------------------------------- readings

    @isTest
    static void aMeterCanOnlyHaveOneBaseline() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Meter_Reading__c second = BillSplitTestData.readingRecord(s.meter.Id, 'Baseline', Date.today().addDays(-200), 1000, null);
        assertBlocked(Database.insert(second, false), 'already has a baseline');
    }

    @isTest
    static void readingsMustNotGoBackwards() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        // Closing reading is 1278 on the period end; baseline is 1240 earlier.
        Meter_Reading__c lower = BillSplitTestData.readingRecord(s.meter.Id, 'Interim', s.bill.Period_End__c.addDays(5), 1200, null);
        assertBlocked(Database.insert(lower, false), 'lower than the earlier reading');

        Meter_Reading__c higher = BillSplitTestData.readingRecord(s.meter.Id, 'Interim', s.bill.Period_Start__c.addDays(5), 1300, null);
        assertBlocked(Database.insert(higher, false), 'higher than the later reading');

        Meter_Reading__c fine = BillSplitTestData.readingRecord(s.meter.Id, 'Interim', s.bill.Period_Start__c.addDays(5), 1260, null);
        System.assert(Database.insert(fine, false).isSuccess(), 'A reading between the two is allowed.');
    }

    @isTest
    static void aBillCanOnlyHaveOneClosingReadingPerMeter() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Meter_Reading__c dup = BillSplitTestData.readingRecord(s.meter.Id, 'Bill Close', s.bill.Period_End__c, 1278, s.bill.Id);
        assertBlocked(Database.insert(dup, false), 'already has a closing reading');
    }

    @isTest
    static void aClosingReadingNeedsABill() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Meter_Reading__c r = BillSplitTestData.readingRecord(s.meter.Id, 'Bill Close', Date.today(), 1290, null);
        assertBlocked(Database.insert(r, false), 'Select the Utility Bill');
    }

    // ---------------------------------------------------------------- bills and accounts

    @isTest
    static void theUtilityAccountKeyIsSet() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        String key = [SELECT Unique_Key__c FROM Utility_Account__c WHERE Id = :s.account.Id].Unique_Key__c;
        System.assertEquals(String.valueOf(s.property.Id) + '|Water|ACC-1001', key);
    }

    @isTest
    static void aNewBillDefaultsToDraftAndGetsAKey() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Utility_Bill__c bill = [SELECT Status__c, Unique_Key__c FROM Utility_Bill__c WHERE Id = :s.bill.Id];
        System.assertEquals('Draft', bill.Status__c);
        System.assertEquals(String.valueOf(s.account.Id) + '|BILL-1', bill.Unique_Key__c);
    }

    @isTest
    static void aBillNumberCannotBeUsedTwiceOnTheSameAccount() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Date start2 = s.bill.Period_End__c.addDays(1);
        Utility_Bill__c dup = BillSplitTestData.billRecord(s.account.Id, 'BILL-1', start2, start2.addDays(89), 100, 300.00, null);
        Database.SaveResult sr = Database.insert(dup, false);
        System.assert(!sr.isSuccess(), 'Duplicate bill numbers should be blocked.');
    }

    @isTest
    static void billingPeriodsCannotOverlap() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Utility_Bill__c overlapping = BillSplitTestData.billRecord(
            s.account.Id, 'BILL-OVERLAP', s.bill.Period_Start__c.addDays(30), s.bill.Period_End__c.addDays(30), 100, 300.00, null);
        assertBlocked(Database.insert(overlapping, false), 'overlaps bill BILL-1');
    }

    @isTest
    static void changingFiguresAfterCalculationSendsTheBillBackToDraft() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitService.calculateAndSave(s.bill.Id);
        System.assertEquals('Calculated', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :s.bill.Id].Status__c);

        update new Utility_Bill__c(Id = s.bill.Id, Total_Amount__c = 500.00);
        Utility_Bill__c bill = [SELECT Status__c, Calculated_At__c FROM Utility_Bill__c WHERE Id = :s.bill.Id];
        System.assertEquals('Draft', bill.Status__c);
        System.assertEquals(null, bill.Calculated_At__c);
    }

    @isTest
    static void changingTheClosingReadingAfterCalculationSendsTheBillBackToDraft() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitService.calculateAndSave(s.bill.Id);

        update new Meter_Reading__c(Id = s.closing.Id, Reading_Value__c = 1279);
        System.assertEquals('Draft', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :s.bill.Id].Status__c);

        BillSplitService.calculateAndSave(s.bill.Id);
        delete s.closing;
        System.assertEquals('Draft', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :s.bill.Id].Status__c);
    }
}