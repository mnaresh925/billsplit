@isTest
private class BillSplitCalculatorTest {

    private static Id fakeId(Schema.SObjectType t, Integer n) {
        return Id.valueOf(t.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }

    private static BillSplitCalculator.UnitInput unit(String label, Integer n, Boolean metered, Decimal opening, Decimal closing) {
        BillSplitCalculator.UnitInput u = new BillSplitCalculator.UnitInput();
        u.unitId = fakeId(Unit__c.SObjectType, n);
        u.label = label;
        if (metered) {
            u.meterId = fakeId(Meter__c.SObjectType, n);
            u.openingReading = opening;
            u.closingReading = closing;
        }
        return u;
    }

    // Unit A is the residual unit, Unit B has the sub-meter.
    private static BillSplitCalculator.SplitInput makeInput(Decimal totalUnits, Decimal totalAmount, Decimal supply,
                                                             String method, Decimal opening, Decimal closing) {
        BillSplitCalculator.SplitInput i = new BillSplitCalculator.SplitInput();
        i.totalUnits = totalUnits;
        i.totalAmount = totalAmount;
        i.supplyCharge = supply;
        i.splitMethod = method;
        i.units.add(unit('Unit A', 1, false, null, null));
        i.units.add(unit('Unit B', 2, true, opening, closing));
        return i;
    }

    private static void assertDec(Decimal expected, Decimal actual, String what) {
        System.assertNotEquals(null, actual, what + ' was null');
        System.assert((expected - actual).abs() < 0.0001, what + ': expected ' + expected + ' but was ' + actual);
    }

    private static void assertError(BillSplitCalculator.SplitResult res, String fragment) {
        System.assert(!res.errors.isEmpty(), 'Expected an error containing "' + fragment + '" but there were none.');
        System.assert(String.join(res.errors, ' ').contains(fragment),
            'Expected an error containing "' + fragment + '" but got: ' + String.join(res.errors, ' | '));
    }

    @isTest
    static void workedExampleSplitsByConsumptionAndSupplyEvenly() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(
            makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, 1278));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        BillSplitCalculator.UnitResult a = res.units[0];
        BillSplitCalculator.UnitResult b = res.units[1];
        assertDec(82, a.unitsConsumed, 'Unit A units');
        assertDec(38, b.unitsConsumed, 'Unit B units');
        assertDec(287.00, a.usageAmount, 'Unit A usage');
        assertDec(133.00, b.usageAmount, 'Unit B usage');
        assertDec(30.00, a.supplyAmount, 'Unit A supply');
        assertDec(30.00, b.supplyAmount, 'Unit B supply');
        assertDec(317.00, a.totalAmount, 'Unit A total');
        assertDec(163.00, b.totalAmount, 'Unit B total');
        System.assert(a.isResidual, 'Unit A is the residual unit');
        System.assert(!b.isResidual, 'Unit B is metered');
        assertDec(31.67, b.usageSharePercent, 'Unit B share');
        System.assert(String.isNotBlank(res.notes), 'Notes explain the working');
        System.assert(res.notes.contains('Check:'), 'Notes include the check line');
    }

    @isTest
    static void withoutSupplyChargeOnlyUsageIsSplit() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(
            makeInput(120, 480.00, null, 'Submeter Residual', 1240, 1278));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        assertDec(328.00, res.units[0].totalAmount, 'Unit A total');
        assertDec(152.00, res.units[1].totalAmount, 'Unit B total');
        assertDec(0, res.units[0].supplyAmount, 'Unit A supply');
    }

    @isTest
    static void oddCentGoesToTheResidualUnitAndSharesStillAddUp() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(
            makeInput(120, 100.01, 0.01, 'Submeter Residual', 1000, 1037));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        assertDec(69.17, res.units[0].totalAmount, 'Unit A total');
        assertDec(30.84, res.units[1].totalAmount, 'Unit B total');
        assertDec(100.01, res.units[0].totalAmount + res.units[1].totalAmount, 'Sum of shares');
    }

    @isTest
    static void equalMethodSplitsEverythingInHalf() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(
            makeInput(120, 480.00, 60.00, 'Equal', null, null));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        assertDec(240.00, res.units[0].totalAmount, 'Unit A total');
        assertDec(240.00, res.units[1].totalAmount, 'Unit B total');
        assertDec(60, res.units[0].unitsConsumed, 'Unit A units');
        assertDec(60, res.units[1].unitsConsumed, 'Unit B units');
    }

    @isTest
    static void submeterUsingTheWholeBillLeavesResidualWithSupplyShareOnly() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(
            makeInput(120, 480.00, 60.00, 'Submeter Residual', 0, 120));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        assertDec(30.00, res.units[0].totalAmount, 'Unit A total');
        assertDec(450.00, res.units[1].totalAmount, 'Unit B total');
        System.assertEquals(1, res.warnings.size(), 'One warning about zero consumption');
    }

    @isTest
    static void submeterWithNoConsumptionPaysSupplyShareOnly() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(
            makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, 1240));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        assertDec(450.00, res.units[0].totalAmount, 'Unit A total');
        assertDec(30.00, res.units[1].totalAmount, 'Unit B total');
        System.assertEquals(1, res.warnings.size(), 'One warning about no consumption');
    }

    @isTest
    static void submeterUsingMoreThanTheBillIsAnError() {
        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, 1400)),
            'more than the bill total');
    }

    @isTest
    static void closingReadingBelowOpeningIsAnError() {
        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, 60.00, 'Submeter Residual', 1278, 1240)),
            'lower than the opening reading');
    }

    @isTest
    static void missingReadingsAreErrors() {
        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, 60.00, 'Submeter Residual', null, 1278)),
            'no opening reading');
        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, null)),
            'no closing reading');
    }

    @isTest
    static void invalidBillFiguresAreErrors() {
        assertError(BillSplitCalculator.calculate(makeInput(0, 480.00, 60.00, 'Submeter Residual', 1240, 1278)),
            'greater than zero');
        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, -1, 'Submeter Residual', 1240, 1278)),
            'Supply charge');
        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, 500.00, 'Submeter Residual', 1240, 1278)),
            'Supply charge');
        assertError(BillSplitCalculator.calculate(makeInput(120, -5, null, 'Submeter Residual', 1240, 1278)),
            'zero or more');
    }

    @isTest
    static void unsupportedSituationsAreErrors() {
        assertError(BillSplitCalculator.calculate(null), 'No bill data');

        BillSplitCalculator.SplitInput oneUnit = makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, 1278);
        oneUnit.units.remove(0);
        assertError(BillSplitCalculator.calculate(oneUnit), 'exactly 2 units');

        assertError(BillSplitCalculator.calculate(makeInput(120, 480.00, 60.00, 'Custom', 1240, 1278)), 'not supported');

        BillSplitCalculator.SplitInput noMeter = makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, 1278);
        noMeter.units[1].meterId = null;
        assertError(BillSplitCalculator.calculate(noMeter), 'No unit has an active sub-meter');

        BillSplitCalculator.SplitInput twoMeters = makeInput(120, 480.00, 60.00, 'Submeter Residual', 1240, 1278);
        twoMeters.units[0].meterId = fakeId(Meter__c.SObjectType, 9);
        assertError(BillSplitCalculator.calculate(twoMeters), 'Both units have a sub-meter');
    }

    @isTest
    static void blankMethodDefaultsToSubmeterResidual() {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(makeInput(120, 480.00, 60.00, null, 1240, 1278));
        System.assert(res.isValid(), String.join(res.errors, ' '));
        assertDec(163.00, res.units[1].totalAmount, 'Unit B total');
    }
}