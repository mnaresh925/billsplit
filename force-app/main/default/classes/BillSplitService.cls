/**
 * Loads a bill and its related data, runs BillSplitCalculator, and stores the result as one
 * Bill_Allocation__c per unit. preview() never writes. calculateAndSave() writes in one transaction.
 *
 * The class runs with sharing but in system mode for field and object access, because staff only have
 * read access to allocations (they are written by this service). Callers must check permissions first:
 * the Phase 3 controller enforces them.
 */
public with sharing class BillSplitService {

    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_CALCULATED = 'Calculated';
    private static final String STATUS_SENT = 'Sent';

    @TestVisible private static Boolean reopenPermissionOverride;

    public class SplitContext {
        public Utility_Bill__c bill;
        public List<Unit__c> units;
        public Meter__c meter;
        public Meter_Reading__c opening;
        public Meter_Reading__c closing;
        public BillSplitCalculator.SplitInput input;
        public List<String> warnings = new List<String>();
    }

    /** Calculates without saving. Throws BillSplitException when the data cannot be loaded. */
    public static BillSplitCalculator.SplitResult preview(Id billId) {
        return run(buildContext(billId, false));
    }

    /** Calculates and stores the allocations. Throws BillSplitException when the split is not valid. */
    public static BillSplitCalculator.SplitResult calculateAndSave(Id billId) {
        SplitContext ctx = buildContext(billId, true);
        if (ctx.bill.Status__c == STATUS_SENT && !canReopen()) {
            throw new BillSplitException('This bill has been sent. Ask a user who can reopen sent bills to recalculate it.');
        }
        BillSplitCalculator.SplitResult res = run(ctx);
        if (!res.errors.isEmpty()) {
            throw new BillSplitException(String.join(res.errors, ' '));
        }
        save(ctx, res);
        return res;
    }

    private static Boolean canReopen() {
        if (reopenPermissionOverride != null) {
            return reopenPermissionOverride;
        }
        return FeatureManagement.checkPermission('Reopen_Sent_Bill');
    }

    private static BillSplitCalculator.SplitResult run(SplitContext ctx) {
        BillSplitCalculator.SplitResult res = BillSplitCalculator.calculate(ctx.input);
        res.warnings.addAll(ctx.warnings);
        return res;
    }

    // ------------------------------------------------------------------ loading

    private static SplitContext buildContext(Id billId, Boolean forUpdate) {
        if (billId == null) {
            throw new BillSplitException('A bill is required.');
        }
        List<Utility_Bill__c> bills;
        if (forUpdate) {
            bills = [
                SELECT Id, Name, Status__c, Split_Method__c, Total_Units_Consumed__c, Total_Amount__c,
                       Supply_Charge__c, Period_Start__c, Period_End__c, Utility_Account__c,
                       Utility_Account__r.Property__c
                FROM Utility_Bill__c WHERE Id = :billId FOR UPDATE
            ];
        } else {
            bills = [
                SELECT Id, Name, Status__c, Split_Method__c, Total_Units_Consumed__c, Total_Amount__c,
                       Supply_Charge__c, Period_Start__c, Period_End__c, Utility_Account__c,
                       Utility_Account__r.Property__c
                FROM Utility_Bill__c WHERE Id = :billId
            ];
        }
        if (bills.isEmpty()) {
            throw new BillSplitException('The bill could not be found.');
        }

        SplitContext ctx = new SplitContext();
        ctx.bill = bills[0];
        Id propertyId = ctx.bill.Utility_Account__r.Property__c;
        Id accountId = ctx.bill.Utility_Account__c;

        ctx.units = [SELECT Id, Name FROM Unit__c WHERE Property__c = :propertyId ORDER BY Name];
        if (ctx.units.size() != 2) {
            throw new BillSplitException('Bill splitting needs exactly 2 units, but this property has ' + ctx.units.size() + '.');
        }

        String method = String.isBlank(ctx.bill.Split_Method__c)
            ? BillSplitCalculator.METHOD_SUBMETER_RESIDUAL : ctx.bill.Split_Method__c;

        if (method == BillSplitCalculator.METHOD_SUBMETER_RESIDUAL) {
            loadMeterAndReadings(ctx, accountId);
        }

        BillSplitCalculator.SplitInput input = new BillSplitCalculator.SplitInput();
        input.totalUnits = ctx.bill.Total_Units_Consumed__c;
        input.totalAmount = ctx.bill.Total_Amount__c;
        input.supplyCharge = ctx.bill.Supply_Charge__c;
        input.splitMethod = method;
        for (Unit__c u : ctx.units) {
            BillSplitCalculator.UnitInput ui = new BillSplitCalculator.UnitInput();
            ui.unitId = u.Id;
            ui.label = u.Name;
            if (ctx.meter != null && ctx.meter.Unit__c == u.Id) {
                ui.meterId = ctx.meter.Id;
                ui.openingReading = ctx.opening == null ? null : ctx.opening.Reading_Value__c;
                ui.closingReading = ctx.closing == null ? null : ctx.closing.Reading_Value__c;
            }
            input.units.add(ui);
        }
        ctx.input = input;
        return ctx;
    }

    private static void loadMeterAndReadings(SplitContext ctx, Id accountId) {
        List<Meter__c> meters = [
            SELECT Id, Name, Unit__c FROM Meter__c
            WHERE Utility_Account__c = :accountId AND Meter_Role__c = 'Sub' AND Active__c = true
        ];
        if (meters.size() > 1) {
            throw new BillSplitException('This utility account has more than one active sub-meter. Only one is supported.');
        }
        if (meters.isEmpty()) {
            return;
        }
        Meter__c meter = meters[0];
        Boolean serves = false;
        for (Unit__c u : ctx.units) {
            if (u.Id == meter.Unit__c) {
                serves = true;
            }
        }
        if (!serves) {
            throw new BillSplitException('Sub-meter ' + meter.Name + ' does not serve a unit of this property.');
        }
        ctx.meter = meter;

        Id meterId = meter.Id;
        Id billId = ctx.bill.Id;
        List<Meter_Reading__c> closings = [
            SELECT Id, Reading_Date__c, Reading_Value__c FROM Meter_Reading__c
            WHERE Meter__c = :meterId AND Utility_Bill__c = :billId AND Reading_Type__c = 'Bill Close'
            ORDER BY Reading_Date__c DESC LIMIT 2
        ];
        if (closings.size() > 1) {
            throw new BillSplitException('Sub-meter ' + meter.Name + ' has more than one closing reading for this bill.');
        }
        if (closings.isEmpty()) {
            return;
        }
        ctx.closing = closings[0];
        Id closingId = ctx.closing.Id;
        Date closingDate = ctx.closing.Reading_Date__c;
        List<Meter_Reading__c> openings = [
            SELECT Id, Reading_Date__c, Reading_Value__c FROM Meter_Reading__c
            WHERE Meter__c = :meterId AND Reading_Type__c IN ('Baseline', 'Bill Close')
              AND Reading_Date__c < :closingDate AND Id != :closingId
            ORDER BY Reading_Date__c DESC, CreatedDate DESC LIMIT 1
        ];
        if (!openings.isEmpty()) {
            ctx.opening = openings[0];
        }

        Date periodEnd = ctx.bill.Period_End__c;
        if (periodEnd != null && closingDate != null) {
            Integer gap = Math.abs(closingDate.daysBetween(periodEnd));
            if (gap > BillSplitSettings.readingToleranceDays()) {
                ctx.warnings.add('The closing reading is dated ' + closingDate.format() + ', which is ' + gap
                    + ' days from the bill period end ' + periodEnd.format() + '.');
            }
        }
    }

    // ------------------------------------------------------------------ saving

    private static void save(SplitContext ctx, BillSplitCalculator.SplitResult res) {
        Id billId = ctx.bill.Id;
        List<Bill_Allocation__c> rows = new List<Bill_Allocation__c>();
        for (BillSplitCalculator.UnitResult ur : res.units) {
            rows.add(new Bill_Allocation__c(
                Utility_Bill__c = billId,
                Unit__c = ur.unitId,
                Unique_Key__c = String.valueOf(billId) + '|' + String.valueOf(ur.unitId),
                Meter__c = ur.meterId,
                Is_Residual__c = ur.isResidual,
                Opening_Reading__c = ur.openingReading,
                Closing_Reading__c = ur.closingReading,
                Units_Consumed__c = ur.unitsConsumed,
                Usage_Share_Percent__c = ur.usageSharePercent,
                Usage_Amount__c = ur.usageAmount,
                Supply_Amount__c = ur.supplyAmount,
                Total_Amount__c = ur.totalAmount,
                Calculation_Notes__c = res.notes
            ));
        }
        Savepoint sp = Database.setSavepoint();
        try {
            Database.upsert(rows, Bill_Allocation__c.Unique_Key__c, true);
            update new Utility_Bill__c(Id = billId, Status__c = STATUS_CALCULATED, Calculated_At__c = System.now());
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new BillSplitException('The split could not be saved: ' + e.getDmlMessage(0));
        }
    }
}