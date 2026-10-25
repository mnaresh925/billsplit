/**
 * Builds the subject, HTML body and plain text body of the bill split email.
 * Pure: no SOQL, no DML, no sending. Money and dates are formatted here so the output does not depend on
 * the running user's locale.
 */
public with sharing class BillSplitEmailBuilder {

    public class UnitRow {
        public String unitName;
        public Boolean isSubmetered = false;
        public Decimal unitsConsumed;
        public Decimal usageAmount;
        public Decimal supplyAmount;
        public Decimal totalAmount;
    }

    public class Model {
        public String recipientFirstName;
        public String utilityType;
        public String propertyName;
        public String billNumber;
        public Date periodStart;
        public Date periodEnd;
        public Date dueDate;
        public Decimal totalUnits;
        public String unitOfMeasure;
        public Decimal totalAmount;
        public Decimal supplyCharge;
        public String methodText;
        public String footer;
        public List<UnitRow> rows = new List<UnitRow>();
    }

    public class Email {
        public String subject;
        public String htmlBody;
        public String plainBody;
    }

    public static Email build(Model m) {
        Email e = new Email();
        e.subject = subject(m);
        e.plainBody = plain(m);
        e.htmlBody = html(m);
        return e;
    }

    // ------------------------------------------------------------------ formatting

    public static String money(Decimal value) {
        if (value == null) {
            return '';
        }
        Decimal rounded = value.setScale(2, RoundingMode.HALF_UP);
        String[] parts = rounded.abs().toPlainString().split('\\.');
        String whole = parts[0];
        String grouped = '';
        while (whole.length() > 3) {
            grouped = ',' + whole.substring(whole.length() - 3) + grouped;
            whole = whole.substring(0, whole.length() - 3);
        }
        grouped = whole + grouped;
        String cents = parts.size() > 1 ? parts[1] : '00';
        return (rounded < 0 ? '-' : '') + '$' + grouped + '.' + cents;
    }

    public static String formatDate(Date d) {
        if (d == null) {
            return '';
        }
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('d MMM yyyy');
    }

    public static String quantity(Decimal value) {
        if (value == null) {
            return '';
        }
        Decimal d = value.stripTrailingZeros();
        return d.scale() < 0 ? d.setScale(0).toPlainString() : d.toPlainString();
    }

    // ------------------------------------------------------------------ parts

    private static String subject(Model m) {
        return nz(m.utilityType) + ' bill split for ' + nz(m.propertyName) + ', '
            + formatDate(m.periodStart) + ' to ' + formatDate(m.periodEnd);
    }

    private static String greeting(Model m) {
        return String.isBlank(m.recipientFirstName) ? 'Hello,' : 'Hello ' + m.recipientFirstName.trim() + ',';
    }

    private static String intro(Model m) {
        return 'Here is how the ' + nz(m.utilityType).toLowerCase() + ' bill for ' + nz(m.propertyName)
            + ' has been split between the two units.';
    }

    private static List<String> summaryLines(Model m) {
        List<String> lines = new List<String>();
        lines.add('Bill number: ' + nz(m.billNumber));
        lines.add('Billing period: ' + formatDate(m.periodStart) + ' to ' + formatDate(m.periodEnd));
        if (m.dueDate != null) {
            lines.add('Due date: ' + formatDate(m.dueDate));
        }
        lines.add('Council usage: ' + quantity(m.totalUnits) + ' ' + nz(m.unitOfMeasure));
        lines.add('Bill total: ' + money(m.totalAmount));
        if (m.supplyCharge != null && m.supplyCharge > 0) {
            lines.add('Includes a fixed supply charge of ' + money(m.supplyCharge) + ', shared equally.');
        }
        return lines;
    }

    private static String plain(Model m) {
        List<String> out = new List<String>();
        out.add(greeting(m));
        out.add('');
        out.add(intro(m));
        out.add('');
        out.addAll(summaryLines(m));
        out.add('');
        for (UnitRow r : m.rows) {
            out.add(nz(r.unitName) + (r.isSubmetered ? ' (sub-metered)' : '') + ': '
                + quantity(r.unitsConsumed) + ' ' + nz(m.unitOfMeasure) + ', usage ' + money(r.usageAmount)
                + ', supply ' + money(r.supplyAmount) + ', amount payable ' + money(r.totalAmount));
        }
        if (String.isNotBlank(m.methodText)) {
            out.add('');
            out.add(m.methodText);
        }
        if (String.isNotBlank(m.footer)) {
            out.add('');
            out.add(m.footer);
        }
        return String.join(out, '\n');
    }

    private static String html(Model m) {
        String tdStyle = 'padding:6px 10px;border-bottom:1px solid #dddbda;';
        String thStyle = 'padding:6px 10px;border-bottom:2px solid #dddbda;text-align:left;';
        List<String> out = new List<String>();
        out.add('<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#181818;">');
        out.add('<p>' + esc(greeting(m)) + '</p>');
        out.add('<p>' + esc(intro(m)) + '</p>');
        out.add('<ul style="padding-left:18px;">');
        for (String line : summaryLines(m)) {
            out.add('<li>' + esc(line) + '</li>');
        }
        out.add('</ul>');
        out.add('<table style="border-collapse:collapse;min-width:420px;">');
        out.add('<tr><th style="' + thStyle + '">Unit</th><th style="' + thStyle + 'text-align:right;">Used ('
            + esc(nz(m.unitOfMeasure)) + ')</th><th style="' + thStyle + 'text-align:right;">Usage</th><th style="'
            + thStyle + 'text-align:right;">Supply</th><th style="' + thStyle + 'text-align:right;">Amount payable</th></tr>');
        for (UnitRow r : m.rows) {
            out.add('<tr><td style="' + tdStyle + '">' + esc(nz(r.unitName)) + (r.isSubmetered ? ' (sub-metered)' : '')
                + '</td><td style="' + tdStyle + 'text-align:right;">' + esc(quantity(r.unitsConsumed))
                + '</td><td style="' + tdStyle + 'text-align:right;">' + esc(money(r.usageAmount))
                + '</td><td style="' + tdStyle + 'text-align:right;">' + esc(money(r.supplyAmount))
                + '</td><td style="' + tdStyle + 'text-align:right;font-weight:bold;">' + esc(money(r.totalAmount))
                + '</td></tr>');
        }
        out.add('</table>');
        if (String.isNotBlank(m.methodText)) {
            out.add('<p style="color:#444444;">' + esc(m.methodText) + '</p>');
        }
        if (String.isNotBlank(m.footer)) {
            out.add('<p style="color:#444444;">' + esc(m.footer) + '</p>');
        }
        out.add('</div>');
        return String.join(out, '\n');
    }

    private static String esc(String s) {
        return s == null ? '' : s.escapeHtml4();
    }

    private static String nz(String s) {
        return s == null ? '' : s;
    }
}