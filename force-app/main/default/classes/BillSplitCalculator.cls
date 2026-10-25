/**
 * Pure calculation of how a council bill is split between the two units of a property.
 * No SOQL and no DML: every business rule for the split lives here so it can be unit tested alone.
 *
 * Submeter Residual: the sub-metered unit pays for the units it used, the other unit pays for the rest.
 * Equal: both units split everything 50/50.
 * In both methods the usage charge (total minus supply charge) follows consumption (or 50/50 for Equal)
 * and the supply charge, when present, is split 50/50. The second share is always the remainder,
 * so the two shares add up to the bill total to the cent.
 */
public with sharing class BillSplitCalculator {

    public static final String METHOD_SUBMETER_RESIDUAL = 'Submeter Residual';
    public static final String METHOD_EQUAL = 'Equal';

    public class SplitInput {
        public Decimal totalUnits;
        public Decimal totalAmount;
        public Decimal supplyCharge;
        public String splitMethod;
        public List<UnitInput> units = new List<UnitInput>();
    }

    public class UnitInput {
        public Id unitId;
        public String label;
        public Id meterId;
        public Decimal openingReading;
        public Decimal closingReading;
    }

    public class UnitResult {
        public Id unitId;
        public String label;
        public Id meterId;
        public Decimal openingReading;
        public Decimal closingReading;
        public Decimal unitsConsumed;
        public Decimal usageSharePercent;
        public Decimal usageAmount;
        public Decimal supplyAmount;
        public Decimal totalAmount;
        public Boolean isResidual = false;
    }

    public class SplitResult {
        public List<UnitResult> units = new List<UnitResult>();
        public List<String> errors = new List<String>();
        public List<String> warnings = new List<String>();
        public String notes;
        public Boolean isValid() {
            return errors.isEmpty();
        }
    }

    public static SplitResult calculate(SplitInput input) {
        SplitResult res = new SplitResult();
        validate(input, res);
        if (!res.errors.isEmpty()) {
            return res;
        }

        Decimal supply = input.supplyCharge == null ? 0 : input.supplyCharge;
        Decimal usageCharge = input.totalAmount - supply;
        List<String> notes = new List<String>();
        notes.add('Split method: ' + input.splitMethod);
        notes.add('Bill: ' + fmtUnits(input.totalUnits) + ' units, total ' + fmtMoney(input.totalAmount)
            + ', supply charge ' + fmtMoney(supply) + ', usage charge ' + fmtMoney(usageCharge));

        if (input.splitMethod == METHOD_EQUAL) {
            splitEqual(input, usageCharge, supply, res, notes);
        } else {
            splitBySubmeter(input, usageCharge, supply, res, notes);
        }

        Decimal sum = 0;
        List<String> totals = new List<String>();
        for (UnitResult u : res.units) {
            sum += u.totalAmount;
            totals.add(fmtMoney(u.totalAmount));
            notes.add(u.label + ' total: ' + fmtMoney(u.usageAmount) + ' + ' + fmtMoney(u.supplyAmount)
                + ' = ' + fmtMoney(u.totalAmount));
        }
        notes.add('Check: ' + String.join(totals, ' + ') + ' = ' + fmtMoney(sum));
        if ((sum - input.totalAmount).abs() >= 0.005) {
            res.errors.add('The unit shares add up to ' + fmtMoney(sum) + ' but the bill total is '
                + fmtMoney(input.totalAmount) + '.');
        }
        res.notes = String.join(notes, '\n');
        return res;
    }

    // ------------------------------------------------------------------ validation

    private static void validate(SplitInput input, SplitResult res) {
        if (input == null) {
            res.errors.add('No bill data was supplied.');
            return;
        }
        if (String.isBlank(input.splitMethod)) {
            input.splitMethod = METHOD_SUBMETER_RESIDUAL;
        }
        if (input.totalUnits == null || input.totalUnits <= 0) {
            res.errors.add('Total units consumed on the bill must be greater than zero.');
        }
        if (input.totalAmount == null || input.totalAmount < 0) {
            res.errors.add('Total amount on the bill must be zero or more.');
        } else if (input.supplyCharge != null && (input.supplyCharge < 0 || input.supplyCharge > input.totalAmount)) {
            res.errors.add('Supply charge must be between zero and the bill total amount.');
        }
        if (input.units == null || input.units.size() != 2) {
            Integer n = input.units == null ? 0 : input.units.size();
            res.errors.add('Bill splitting needs exactly 2 units, but this property has ' + n + '.');
            return;
        }
        if (input.splitMethod != METHOD_SUBMETER_RESIDUAL && input.splitMethod != METHOD_EQUAL) {
            res.errors.add('Split method "' + input.splitMethod + '" is not supported.');
            return;
        }
        if (input.splitMethod == METHOD_SUBMETER_RESIDUAL) {
            validateSubmeter(input, res);
        }
    }

    private static void validateSubmeter(SplitInput input, SplitResult res) {
        Integer metered = 0;
        UnitInput sub;
        for (UnitInput u : input.units) {
            if (u.meterId != null) {
                metered++;
                sub = u;
            }
        }
        if (metered == 0) {
            res.errors.add('No unit has an active sub-meter. Add a sub-meter, or use the Equal split method.');
            return;
        }
        if (metered > 1) {
            res.errors.add('Both units have a sub-meter. Only one sub-meter per property is supported.');
            return;
        }
        if (sub.openingReading == null) {
            res.errors.add('There is no opening reading for ' + labelOf(sub) + '. Add a baseline reading for its sub-meter.');
        }
        if (sub.closingReading == null) {
            res.errors.add('There is no closing reading for ' + labelOf(sub) + '. Enter the closing reading for this bill.');
        }
        if (sub.openingReading != null && sub.closingReading != null) {
            if (sub.closingReading < sub.openingReading) {
                res.errors.add('The closing reading ' + fmtUnits(sub.closingReading) + ' for ' + labelOf(sub)
                    + ' is lower than the opening reading ' + fmtUnits(sub.openingReading) + '.');
            } else if (input.totalUnits != null && (sub.closingReading - sub.openingReading) > input.totalUnits) {
                res.errors.add('The sub-meter used ' + fmtUnits(sub.closingReading - sub.openingReading)
                    + ' units, which is more than the bill total of ' + fmtUnits(input.totalUnits) + '.');
            }
        }
    }

    // ------------------------------------------------------------------ methods

    private static void splitBySubmeter(SplitInput input, Decimal usageCharge, Decimal supply,
                                        SplitResult res, List<String> notes) {
        UnitInput sub;
        UnitInput resid;
        for (UnitInput u : input.units) {
            if (u.meterId != null) {
                sub = u;
            } else {
                resid = u;
            }
        }
        Decimal subUnits = (sub.closingReading - sub.openingReading).setScale(3, System.RoundingMode.HALF_UP);
        Decimal residUnits = (input.totalUnits - subUnits).setScale(3, System.RoundingMode.HALF_UP);

        Decimal subUsage = (usageCharge * subUnits).divide(input.totalUnits, 2, System.RoundingMode.HALF_UP);
        Decimal residUsage = (usageCharge - subUsage).setScale(2, System.RoundingMode.HALF_UP);
        Decimal subSupply = supply.divide(2, 2, System.RoundingMode.HALF_UP);
        Decimal residSupply = (supply - subSupply).setScale(2, System.RoundingMode.HALF_UP);

        notes.add(labelOf(sub) + ' (sub-meter): closing ' + fmtUnits(sub.closingReading) + ' - opening '
            + fmtUnits(sub.openingReading) + ' = ' + fmtUnits(subUnits) + ' units');
        notes.add(labelOf(resid) + ' (residual): ' + fmtUnits(input.totalUnits) + ' - ' + fmtUnits(subUnits)
            + ' = ' + fmtUnits(residUnits) + ' units');
        notes.add(labelOf(sub) + ' usage: ' + fmtMoney(usageCharge) + ' x ' + fmtUnits(subUnits) + ' / '
            + fmtUnits(input.totalUnits) + ' = ' + fmtMoney(subUsage));
        notes.add(labelOf(resid) + ' usage: ' + fmtMoney(usageCharge) + ' - ' + fmtMoney(subUsage) + ' = '
            + fmtMoney(residUsage) + ' (remainder)');
        if (supply > 0) {
            notes.add('Supply charge ' + fmtMoney(supply) + ' split 50/50: ' + labelOf(sub) + ' ' + fmtMoney(subSupply)
                + ', ' + labelOf(resid) + ' ' + fmtMoney(residSupply));
        }

        if (residUnits == 0) {
            res.warnings.add(labelOf(resid) + ' has no consumption: the sub-meter used the full bill.');
        }
        if (subUnits == 0) {
            res.warnings.add(labelOf(sub) + ' recorded no consumption, so it pays only its supply share.');
        }

        for (UnitInput u : input.units) {
            Boolean isSub = u.meterId != null;
            UnitResult r = newResult(u,
                isSub ? subUnits : residUnits,
                isSub ? subUsage : residUsage,
                isSub ? subSupply : residSupply,
                input.totalUnits);
            r.isResidual = !isSub;
            if (isSub) {
                r.meterId = u.meterId;
                r.openingReading = u.openingReading;
                r.closingReading = u.closingReading;
            }
            res.units.add(r);
        }
    }

    private static void splitEqual(SplitInput input, Decimal usageCharge, Decimal supply,
                                   SplitResult res, List<String> notes) {
        Decimal unitsFirst = input.totalUnits.divide(2, 3, System.RoundingMode.HALF_UP);
        Decimal unitsSecond = (input.totalUnits - unitsFirst).setScale(3, System.RoundingMode.HALF_UP);
        Decimal usageFirst = usageCharge.divide(2, 2, System.RoundingMode.HALF_UP);
        Decimal usageSecond = (usageCharge - usageFirst).setScale(2, System.RoundingMode.HALF_UP);
        Decimal supplyFirst = supply.divide(2, 2, System.RoundingMode.HALF_UP);
        Decimal supplySecond = (supply - supplyFirst).setScale(2, System.RoundingMode.HALF_UP);

        notes.add('Units and charges are split 50/50 between ' + labelOf(input.units[0]) + ' and ' + labelOf(input.units[1]) + '.');
        res.units.add(newResult(input.units[0], unitsFirst, usageFirst, supplyFirst, input.totalUnits));
        res.units.add(newResult(input.units[1], unitsSecond, usageSecond, supplySecond, input.totalUnits));
    }

    // ------------------------------------------------------------------ helpers

    private static UnitResult newResult(UnitInput u, Decimal units, Decimal usage, Decimal supply, Decimal totalUnits) {
        UnitResult r = new UnitResult();
        r.unitId = u.unitId;
        r.label = labelOf(u);
        r.unitsConsumed = units;
        r.usageSharePercent = (units * 100).divide(totalUnits, 2, System.RoundingMode.HALF_UP);
        r.usageAmount = usage;
        r.supplyAmount = supply;
        r.totalAmount = (usage + supply).setScale(2, System.RoundingMode.HALF_UP);
        return r;
    }

    private static String labelOf(UnitInput u) {
        return String.isNotBlank(u.label) ? u.label : String.valueOf(u.unitId);
    }

    private static String fmtMoney(Decimal d) {
        return d.setScale(2, System.RoundingMode.HALF_UP).toPlainString();
    }

    private static String fmtUnits(Decimal d) {
        return d.setScale(3, System.RoundingMode.HALF_UP).toPlainString();
    }
}