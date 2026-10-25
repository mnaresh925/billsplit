/** Test data builders shared by the Bill Split tests. */
@isTest
public class BillSplitTestData {

    public class Scenario {
        public Property__c property;
        public Unit__c unitA;
        public Unit__c unitB;
        public Utility_Account__c account;
        public Meter__c meter;
        public Utility_Bill__c bill;
        public Meter_Reading__c baseline;
        public Meter_Reading__c closing;
    }

    public static Property__c property(String name) {
        Property__c p = new Property__c(
            Display_Name__c = name, Street__c = name, Suburb__c = 'Turner', State__c = 'ACT',
            Postcode__c = '2612', Address_Source__c = 'Manual', Status__c = 'Active'
        );
        insert p;
        return p;
    }

    public static Unit__c unit(Id propertyId, String label) {
        Unit__c u = unitRecord(propertyId, label);
        insert u;
        return u;
    }

    public static Unit__c unitRecord(Id propertyId, String label) {
        return new Unit__c(
            Name = label, Property__c = propertyId, Same_As_Property_Address__c = false,
            Street__c = label + ' Street', Suburb__c = 'Turner', State__c = 'ACT', Postcode__c = '2612',
            Address_Source__c = 'Manual', Status__c = 'Occupied'
        );
    }

    public static Contact contact(String lastName, String email, String alternateEmail) {
        Contact c = new Contact(LastName = lastName, Email = email, Alternate_Billing_Email__c = alternateEmail);
        insert c;
        return c;
    }

    public static Ownership__c ownershipRecord(Id propertyId, Id contactId, Id unitId, String preference) {
        return new Ownership__c(
            Property__c = propertyId, Contact__c = contactId, Unit__c = unitId, Role__c = 'Owner',
            Bill_Email_Preference__c = preference, Receives_Bills__c = true, Start_Date__c = Date.today().addYears(-1)
        );
    }

    public static Utility_Account__c waterAccount(Id propertyId, String accountNumber) {
        Utility_Account__c ua = new Utility_Account__c(
            Property__c = propertyId, Utility_Type__c = 'Water', Provider__c = 'Test Council',
            Account_Number__c = accountNumber, Billing_Frequency__c = 'Quarterly', Unit_Of_Measure__c = 'kL', Active__c = true
        );
        insert ua;
        return ua;
    }

    public static Meter__c meterRecord(Id accountId, Id unitId, String name) {
        return new Meter__c(Name = name, Utility_Account__c = accountId, Meter_Role__c = 'Sub', Unit__c = unitId, Active__c = true);
    }

    public static Meter_Reading__c readingRecord(Id meterId, String type, Date readingDate, Decimal value, Id billId) {
        return new Meter_Reading__c(
            Meter__c = meterId, Reading_Type__c = type, Reading_Date__c = readingDate, Reading_Value__c = value,
            Utility_Bill__c = billId, Source__c = 'Staff App'
        );
    }

    public static Utility_Bill__c billRecord(Id accountId, String billNumber, Date periodStart, Date periodEnd,
                                             Decimal units, Decimal amount, Decimal supply) {
        return new Utility_Bill__c(
            Utility_Account__c = accountId, Bill_Number__c = billNumber, Issue_Date__c = periodEnd.addDays(1),
            Period_Start__c = periodStart, Period_End__c = periodEnd, Total_Units_Consumed__c = units,
            Total_Amount__c = amount, Supply_Charge__c = supply, Split_Method__c = 'Submeter Residual'
        );
    }

    /** The worked example: 120 kL, $480.00 with a $60.00 supply charge, sub-meter 1240 to 1278 on Unit B. */
    public static Scenario scenario() {
        Scenario s = new Scenario();
        s.property = property('12 Banksia St');
        s.unitA = unit(s.property.Id, 'Unit A');
        s.unitB = unit(s.property.Id, 'Unit B');
        s.account = waterAccount(s.property.Id, 'ACC-1001');
        s.meter = meterRecord(s.account.Id, s.unitB.Id, 'SUB-1');
        insert s.meter;
        Date periodEnd = Date.today().addDays(-1);
        Date periodStart = periodEnd.addDays(-90);
        s.baseline = readingRecord(s.meter.Id, 'Baseline', periodStart.addDays(-1), 1240, null);
        insert s.baseline;
        s.bill = billRecord(s.account.Id, 'BILL-1', periodStart, periodEnd, 120, 480.00, 60.00);
        insert s.bill;
        s.closing = readingRecord(s.meter.Id, 'Bill Close', periodEnd, 1278, s.bill.Id);
        insert s.closing;
        return s;
    }
}