@isTest
private class BillSplitEmailBuilderTest {

    private static BillSplitEmailBuilder.Model model() {
        BillSplitEmailBuilder.Model m = new BillSplitEmailBuilder.Model();
        m.recipientFirstName = 'Alex';
        m.utilityType = 'Water';
        m.propertyName = '12 Banksia St';
        m.billNumber = 'BILL-1';
        m.periodStart = Date.newInstance(2026, 4, 1);
        m.periodEnd = Date.newInstance(2026, 6, 30);
        m.dueDate = Date.newInstance(2026, 7, 28);
        m.totalUnits = 120;
        m.unitOfMeasure = 'kL';
        m.totalAmount = 480;
        m.supplyCharge = 60;
        m.methodText = 'Unit B has its own meter.';
        m.footer = 'Reply to this email with questions.';
        BillSplitEmailBuilder.UnitRow a = new BillSplitEmailBuilder.UnitRow();
        a.unitName = 'Unit A';
        a.unitsConsumed = 82;
        a.usageAmount = 287;
        a.supplyAmount = 30;
        a.totalAmount = 317;
        BillSplitEmailBuilder.UnitRow b = new BillSplitEmailBuilder.UnitRow();
        b.unitName = 'Unit B';
        b.isSubmetered = true;
        b.unitsConsumed = 38;
        b.usageAmount = 133;
        b.supplyAmount = 30;
        b.totalAmount = 163;
        m.rows = new List<BillSplitEmailBuilder.UnitRow>{ a, b };
        return m;
    }

    @isTest
    static void formatsMoneyWithoutDependingOnLocale() {
        System.assertEquals('$1,234.50', BillSplitEmailBuilder.money(1234.5));
        System.assertEquals('$163.00', BillSplitEmailBuilder.money(163));
        System.assertEquals('$0.01', BillSplitEmailBuilder.money(0.005));
        System.assertEquals('-$5.00', BillSplitEmailBuilder.money(-5));
        System.assertEquals('$1,000,000.00', BillSplitEmailBuilder.money(1000000));
        System.assertEquals('', BillSplitEmailBuilder.money(null));
    }

    @isTest
    static void formatsQuantities() {
        System.assertEquals('38', BillSplitEmailBuilder.quantity(38.000));
        System.assertEquals('120', BillSplitEmailBuilder.quantity(120));
        System.assertEquals('12.5', BillSplitEmailBuilder.quantity(12.50));
    }

    @isTest
    static void buildsSubjectAndBodies() {
        BillSplitEmailBuilder.Email e = BillSplitEmailBuilder.build(model());

        System.assert(e.subject.startsWith('Water bill split for 12 Banksia St, '), e.subject);
        System.assert(e.plainBody.startsWith('Hello Alex,'));
        System.assert(e.plainBody.contains('Unit B (sub-metered): 38 kL'));
        System.assert(e.plainBody.contains('amount payable $163.00'));
        System.assert(e.plainBody.contains('amount payable $317.00'));
        System.assert(e.plainBody.contains('Includes a fixed supply charge of $60.00'));
        System.assert(e.plainBody.contains('Unit B has its own meter.'));
        System.assert(e.plainBody.contains('Reply to this email with questions.'));
        System.assert(e.htmlBody.contains('<table'));
        System.assert(e.htmlBody.contains('$163.00'));
        System.assert(e.htmlBody.contains('$317.00'));
    }

    @isTest
    static void leavesOutSupplyLineWhenThereIsNoSupplyCharge() {
        BillSplitEmailBuilder.Model m = model();
        m.supplyCharge = null;
        System.assert(!BillSplitEmailBuilder.build(m).plainBody.contains('fixed supply charge'));
        m.supplyCharge = 0;
        System.assert(!BillSplitEmailBuilder.build(m).plainBody.contains('fixed supply charge'));
    }

    @isTest
    static void greetsGenericallyWithoutAFirstName() {
        BillSplitEmailBuilder.Model m = model();
        m.recipientFirstName = null;
        System.assert(BillSplitEmailBuilder.build(m).plainBody.startsWith('Hello,'));
    }

    @isTest
    static void escapesHtmlInTheHtmlBody() {
        BillSplitEmailBuilder.Model m = model();
        m.propertyName = '5 <b>Wattle</b> & Co';
        BillSplitEmailBuilder.Email e = BillSplitEmailBuilder.build(m);
        System.assert(!e.htmlBody.contains('<b>Wattle</b>'), 'Property name must be escaped');
        System.assert(e.htmlBody.contains('&lt;b&gt;Wattle'));
    }
}