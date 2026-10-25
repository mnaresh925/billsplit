/**
 * Read-only data for the owner portal (billSplitOwnerPortal LWC).
 *
 * Runs with sharing and in user mode: a portal user only gets rows the Owner_Access sharing rule has shared
 * with them, and only the fields their permission sets allow. On top of that every method works from the
 * signed-in user's own contact (never an id sent by the browser), shows only bills that have been sent, and
 * returns no details of other owners.
 *
 * Kept separate from the staff controller so the portal permission set grants this one class only.
 */
public with sharing class OwnerPortalController {

    private static final String BILL_SENT = 'Sent';

    @TestVisible private static Id contactIdOverride;

    public class UnitInfo {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String name;
        @AuraEnabled public String address;
        @AuraEnabled public Boolean isMine = false;
    }

    public class AllocationView {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitName;
        @AuraEnabled public Boolean isMine = false;
        @AuraEnabled public Boolean isSubmetered = false;
        @AuraEnabled public Decimal unitsConsumed;
        @AuraEnabled public Decimal sharePercent;
        @AuraEnabled public Decimal usageAmount;
        @AuraEnabled public Decimal supplyAmount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal openingReading;
        @AuraEnabled public Decimal closingReading;
    }

    public class BillView {
        @AuraEnabled public Id billId;
        @AuraEnabled public Id propertyId;
        @AuraEnabled public String propertyName;
        @AuraEnabled public String billNumber;
        @AuraEnabled public String utilityType;
        @AuraEnabled public String unitOfMeasure;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal totalUnits;
        @AuraEnabled public Decimal supplyCharge;
        @AuraEnabled public Decimal usageCharge;
        @AuraEnabled public Decimal myShare;
        @AuraEnabled public String notes;
        @AuraEnabled public List<AllocationView> allocations = new List<AllocationView>();
    }

    public class PropertyView {
        @AuraEnabled public Id propertyId;
        @AuraEnabled public String name;
        @AuraEnabled public String address;
        @AuraEnabled public String councilName;
        @AuraEnabled public String role;
        @AuraEnabled public List<UnitInfo> units = new List<UnitInfo>();
        @AuraEnabled public BillView latestBill;
    }

    // ------------------------------------------------------------------ AuraEnabled

    @AuraEnabled
    public static List<PropertyView> getMyProperties() {
        try {
            return propertiesFor(currentContactId());
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static List<BillView> getBills(Id propertyId) {
        try {
            Id contactId = currentContactId();
            Map<Id, Set<Id>> mine = myUnitsByProperty(contactId);
            if (propertyId == null || !mine.containsKey(propertyId)) {
                throw new BillSplitException('You do not have access to that property.');
            }
            return billsFor(propertyId, null, mine.get(propertyId));
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static BillView getBillDetail(Id billId) {
        try {
            Id contactId = currentContactId();
            Map<Id, Set<Id>> mine = myUnitsByProperty(contactId);
            if (billId == null) {
                throw new BillSplitException('A bill is required.');
            }
            List<Utility_Bill__c> found = [
                SELECT Utility_Account__r.Property__c FROM Utility_Bill__c WHERE Id = :billId WITH USER_MODE
            ];
            if (found.isEmpty() || !mine.containsKey(found[0].Utility_Account__r.Property__c)) {
                throw new BillSplitException('You do not have access to that bill.');
            }
            Id propertyId = found[0].Utility_Account__r.Property__c;
            List<BillView> bills = billsFor(propertyId, billId, mine.get(propertyId));
            if (bills.isEmpty()) {
                throw new BillSplitException('That bill has not been sent yet.');
            }
            return bills[0];
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    // ------------------------------------------------------------------ testable core

    @TestVisible
    private static List<PropertyView> propertiesFor(Id contactId) {
        Map<Id, Set<Id>> mine = myUnitsByProperty(contactId);
        List<PropertyView> views = new List<PropertyView>();
        if (mine.isEmpty()) {
            return views;
        }
        Map<Id, String> roles = new Map<Id, String>();
        for (Ownership__c o : ownerships(contactId)) {
            if (!roles.containsKey(o.Property__c)) {
                roles.put(o.Property__c, o.Role__c);
            }
        }
        Map<Id, List<Unit__c>> unitsByProperty = new Map<Id, List<Unit__c>>();
        for (Unit__c u : [
            SELECT Id, Name, Property__c, Street__c, Suburb__c, State__c, Postcode__c
            FROM Unit__c WHERE Property__c IN :mine.keySet() WITH USER_MODE ORDER BY Name
        ]) {
            if (!unitsByProperty.containsKey(u.Property__c)) {
                unitsByProperty.put(u.Property__c, new List<Unit__c>());
            }
            unitsByProperty.get(u.Property__c).add(u);
        }
        for (Property__c p : [
            SELECT Id, Display_Name__c, Street__c, Suburb__c, State__c, Postcode__c, Council_Name__c
            FROM Property__c WHERE Id IN :mine.keySet() WITH USER_MODE ORDER BY Display_Name__c
        ]) {
            PropertyView v = new PropertyView();
            v.propertyId = p.Id;
            v.name = p.Display_Name__c;
            v.address = address(p.Street__c, p.Suburb__c, p.State__c, p.Postcode__c);
            v.councilName = p.Council_Name__c;
            v.role = roles.get(p.Id);
            Set<Id> myUnits = mine.get(p.Id);
            Boolean wholeProperty = myUnits.isEmpty();
            for (Unit__c u : unitsByProperty.containsKey(p.Id) ? unitsByProperty.get(p.Id) : new List<Unit__c>()) {
                UnitInfo ui = new UnitInfo();
                ui.unitId = u.Id;
                ui.name = u.Name;
                ui.address = address(u.Street__c, u.Suburb__c, u.State__c, u.Postcode__c);
                ui.isMine = wholeProperty || myUnits.contains(u.Id);
                v.units.add(ui);
            }
            List<BillView> latest = billsFor(p.Id, null, myUnits);
            v.latestBill = latest.isEmpty() ? null : latest[0];
            views.add(v);
        }
        return views;
    }

    // ------------------------------------------------------------------ queries

    /**
     * Properties the contact has an active ownership on, mapped to the unit ids they own.
     * An empty set means a property-wide ownership (both units).
     */
    private static Map<Id, Set<Id>> myUnitsByProperty(Id contactId) {
        Map<Id, Set<Id>> mine = new Map<Id, Set<Id>>();
        Set<Id> wholeProperty = new Set<Id>();
        for (Ownership__c o : ownerships(contactId)) {
            if (!mine.containsKey(o.Property__c)) {
                mine.put(o.Property__c, new Set<Id>());
            }
            if (o.Unit__c == null) {
                wholeProperty.add(o.Property__c);
            } else {
                mine.get(o.Property__c).add(o.Unit__c);
            }
        }
        for (Id propertyId : wholeProperty) {
            mine.get(propertyId).clear();
        }
        return mine;
    }

    private static List<Ownership__c> ownerships(Id contactId) {
        return [
            SELECT Property__c, Unit__c, Role__c FROM Ownership__c
            WHERE Contact__c = :contactId AND Is_Active__c = true
            WITH USER_MODE ORDER BY Start_Date__c DESC
        ];
    }

    /** Sent bills for a property, newest first, with their allocations. Pass a bill id to get just that bill. */
    private static List<BillView> billsFor(Id propertyId, Id onlyBillId, Set<Id> myUnits) {
        List<Utility_Bill__c> bills;
        if (onlyBillId != null) {
            bills = [
                SELECT Id, Bill_Number__c, Period_Start__c, Period_End__c, Due_Date__c, Sent_At__c, Total_Amount__c,
                       Total_Units_Consumed__c, Supply_Charge__c, Usage_Charge__c,
                       Utility_Account__r.Utility_Type__c, Utility_Account__r.Unit_Of_Measure__c,
                       Utility_Account__r.Property__r.Display_Name__c
                FROM Utility_Bill__c
                WHERE Id = :onlyBillId AND Utility_Account__r.Property__c = :propertyId AND Status__c = :BILL_SENT
                WITH USER_MODE
            ];
        } else {
            bills = [
                SELECT Id, Bill_Number__c, Period_Start__c, Period_End__c, Due_Date__c, Sent_At__c, Total_Amount__c,
                       Total_Units_Consumed__c, Supply_Charge__c, Usage_Charge__c,
                       Utility_Account__r.Utility_Type__c, Utility_Account__r.Unit_Of_Measure__c,
                       Utility_Account__r.Property__r.Display_Name__c
                FROM Utility_Bill__c
                WHERE Utility_Account__r.Property__c = :propertyId AND Status__c = :BILL_SENT
                WITH USER_MODE ORDER BY Period_End__c DESC, Sent_At__c DESC LIMIT 50
            ];
        }
        Map<Id, List<Bill_Allocation__c>> allocations = new Map<Id, List<Bill_Allocation__c>>();
        for (Bill_Allocation__c a : [
            SELECT Utility_Bill__c, Unit__c, Unit__r.Name, Meter__c, Units_Consumed__c, Usage_Share_Percent__c,
                   Usage_Amount__c, Supply_Amount__c, Total_Amount__c, Opening_Reading__c, Closing_Reading__c,
                   Calculation_Notes__c
            FROM Bill_Allocation__c WHERE Utility_Bill__c IN :bills WITH USER_MODE ORDER BY Unit__r.Name
        ]) {
            if (!allocations.containsKey(a.Utility_Bill__c)) {
                allocations.put(a.Utility_Bill__c, new List<Bill_Allocation__c>());
            }
            allocations.get(a.Utility_Bill__c).add(a);
        }

        Boolean wholeProperty = myUnits.isEmpty();
        List<BillView> views = new List<BillView>();
        for (Utility_Bill__c b : bills) {
            BillView v = new BillView();
            v.billId = b.Id;
            v.propertyId = propertyId;
            v.propertyName = b.Utility_Account__r.Property__r.Display_Name__c;
            v.billNumber = b.Bill_Number__c;
            v.utilityType = b.Utility_Account__r.Utility_Type__c;
            v.unitOfMeasure = b.Utility_Account__r.Unit_Of_Measure__c;
            v.periodStart = b.Period_Start__c;
            v.periodEnd = b.Period_End__c;
            v.dueDate = b.Due_Date__c;
            v.sentAt = b.Sent_At__c;
            v.totalAmount = b.Total_Amount__c;
            v.totalUnits = b.Total_Units_Consumed__c;
            v.supplyCharge = b.Supply_Charge__c;
            v.usageCharge = b.Usage_Charge__c;
            Decimal share = 0;
            Boolean anyMine = false;
            for (Bill_Allocation__c a : allocations.containsKey(b.Id) ? allocations.get(b.Id) : new List<Bill_Allocation__c>()) {
                AllocationView av = new AllocationView();
                av.unitId = a.Unit__c;
                av.unitName = a.Unit__r.Name;
                av.isMine = !wholeProperty && myUnits.contains(a.Unit__c);
                av.isSubmetered = a.Meter__c != null;
                av.unitsConsumed = a.Units_Consumed__c;
                av.sharePercent = a.Usage_Share_Percent__c;
                av.usageAmount = a.Usage_Amount__c;
                av.supplyAmount = a.Supply_Amount__c;
                av.totalAmount = a.Total_Amount__c;
                av.openingReading = a.Opening_Reading__c;
                av.closingReading = a.Closing_Reading__c;
                v.allocations.add(av);
                if (av.isMine) {
                    share += a.Total_Amount__c == null ? 0 : a.Total_Amount__c;
                    anyMine = true;
                }
                if (v.notes == null && String.isNotBlank(a.Calculation_Notes__c)) {
                    v.notes = a.Calculation_Notes__c;
                }
            }
            v.myShare = anyMine ? share : null;
            views.add(v);
        }
        return views;
    }

    // ------------------------------------------------------------------ helpers

    private static Id currentContactId() {
        if (contactIdOverride != null) {
            return contactIdOverride;
        }
        List<User> me = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (me.isEmpty() || me[0].ContactId == null) {
            throw new BillSplitException('This page is for property owners. Sign in with your owner account.');
        }
        return me[0].ContactId;
    }

    private static String address(String street, String suburb, String state, String postcode) {
        List<String> parts = new List<String>();
        for (String p : new List<String>{ street, suburb, state, postcode }) {
            if (String.isNotBlank(p)) {
                parts.add(p);
            }
        }
        return String.join(parts, ', ');
    }

    private static AuraHandledException toAura(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ae = new AuraHandledException(e.getMessage());
        ae.setMessage(e.getMessage());
        return ae;
    }
}