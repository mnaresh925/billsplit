/**
 * Apex controller for the staff bill workbench (billSplitWorkbench LWC).
 *
 * Runs with sharing. Record access is enforced by sharing and by explicit object permission checks.
 * The data is read in system mode for field access on purpose: the workbench only returns the fields it
 * displays, and only to users who can read the object. Writes of allocations are done by BillSplitService,
 * which staff cannot do directly (they have read-only access to allocations).
 *
 * Sending and resending go through BillSplitNotificationService after the Send_Bill_Split permission is checked.
 */
public with sharing class BillSplitController {

    private static final String STATUS_SENT = 'Sent';
    private static final String TYPE_BASELINE = 'Baseline';
    private static final String TYPE_CLOSE = 'Bill Close';

    @TestVisible private static Boolean reopenPermissionOverride;
    @TestVisible private static Boolean sendPermissionOverride;

    public class MeterInfo {
        @AuraEnabled public Id meterId;
        @AuraEnabled public String meterName;
        @AuraEnabled public String unitName;
        @AuraEnabled public Decimal openingValue;
        @AuraEnabled public Date openingDate;
        @AuraEnabled public Id closingId;
        @AuraEnabled public Decimal closingValue;
        @AuraEnabled public Date closingDate;
    }

    public class AllocationRow {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitName;
        @AuraEnabled public Boolean isResidual;
        @AuraEnabled public Decimal unitsConsumed;
        @AuraEnabled public Decimal sharePercent;
        @AuraEnabled public Decimal usageAmount;
        @AuraEnabled public Decimal supplyAmount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public String notes;
    }

    public class NotificationRow {
        @AuraEnabled public Id notificationId;
        @AuraEnabled public String reference;
        @AuraEnabled public String contactName;
        @AuraEnabled public String email;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean canResend = false;
    }

    public class WorkbenchData {
        @AuraEnabled public Id billId;
        @AuraEnabled public String billNumber;
        @AuraEnabled public Id propertyId;
        @AuraEnabled public String propertyName;
        @AuraEnabled public String utilityType;
        @AuraEnabled public String unitOfMeasure;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal totalUnits;
        @AuraEnabled public Decimal supplyCharge;
        @AuraEnabled public Decimal usageCharge;
        @AuraEnabled public String splitMethod;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime calculatedAt;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public Decimal allocatedAmount;
        @AuraEnabled public Decimal variance;
        @AuraEnabled public Boolean needsClosingReading = false;
        @AuraEnabled public Boolean isLocked = false;
        @AuraEnabled public Boolean canEditReading = false;
        @AuraEnabled public Boolean canCalculate = false;
        @AuraEnabled public Boolean canSend = false;
        @AuraEnabled public MeterInfo meter;
        @AuraEnabled public List<AllocationRow> allocations = new List<AllocationRow>();
        @AuraEnabled public List<NotificationRow> notifications = new List<NotificationRow>();
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    // ------------------------------------------------------------------ AuraEnabled

    @AuraEnabled
    public static WorkbenchData getWorkbench(Id billId) {
        try {
            requireRead();
            return load(billId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static WorkbenchData calculate(Id billId) {
        try {
            requireRead();
            if (!Schema.sObjectType.Utility_Bill__c.isUpdateable()) {
                throw new BillSplitException('You do not have permission to calculate bills.');
            }
            BillSplitCalculator.SplitResult res = BillSplitService.calculateAndSave(billId);
            WorkbenchData data = load(billId);
            data.warnings.addAll(res.warnings);
            return data;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static BillSplitNotificationService.Preview getSendPreview(Id billId) {
        try {
            requireRead();
            requireSendPermission();
            return BillSplitNotificationService.preview(billId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static WorkbenchData sendBill(Id billId) {
        try {
            requireRead();
            requireSendPermission();
            BillSplitNotificationService.SendResult res = BillSplitNotificationService.send(billId);
            WorkbenchData data = load(billId);
            data.warnings.addAll(res.messages);
            return data;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static WorkbenchData resendNotification(Id billId, Id notificationId) {
        try {
            requireRead();
            requireSendPermission();
            Integer owned = [
                SELECT COUNT() FROM Bill_Notification__c WHERE Id = :notificationId AND Utility_Bill__c = :billId
            ];
            if (owned == 0) {
                throw new BillSplitException('That notification does not belong to this bill.');
            }
            String failure = BillSplitNotificationService.resend(notificationId);
            WorkbenchData data = load(billId);
            if (failure != null) {
                data.warnings.add(failure);
            }
            return data;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static WorkbenchData saveClosingReading(Id billId, Decimal readingValue, Date readingDate) {
        try {
            requireRead();
            if (readingValue == null || readingDate == null) {
                throw new BillSplitException('Enter the closing reading and its date.');
            }
            Utility_Bill__c bill = loadBill(billId);
            if (bill.Status__c == STATUS_SENT && !canReopen()) {
                throw new BillSplitException('This bill has been sent. Ask a user who can reopen sent bills to change the reading.');
            }
            Meter__c meter = loadSubMeter(bill.Utility_Account__c);
            if (meter == null) {
                throw new BillSplitException('This utility account has no active sub-meter, so no reading is needed.');
            }
            List<Meter_Reading__c> existing = [
                SELECT Id FROM Meter_Reading__c
                WHERE Meter__c = :meter.Id AND Utility_Bill__c = :billId AND Reading_Type__c = :TYPE_CLOSE
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                if (!Schema.sObjectType.Meter_Reading__c.isCreateable()) {
                    throw new BillSplitException('You do not have permission to add meter readings.');
                }
                insert new Meter_Reading__c(
                    Meter__c = meter.Id, Utility_Bill__c = billId, Reading_Type__c = TYPE_CLOSE,
                    Reading_Date__c = readingDate, Reading_Value__c = readingValue, Source__c = 'Staff App'
                );
            } else {
                if (!Schema.sObjectType.Meter_Reading__c.isUpdateable()) {
                    throw new BillSplitException('You do not have permission to change meter readings.');
                }
                update new Meter_Reading__c(
                    Id = existing[0].Id, Reading_Date__c = readingDate, Reading_Value__c = readingValue
                );
            }
            return load(billId);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    // ------------------------------------------------------------------ loading

    private static WorkbenchData load(Id billId) {
        Utility_Bill__c bill = loadBill(billId);
        WorkbenchData d = new WorkbenchData();
        d.billId = bill.Id;
        d.billNumber = bill.Bill_Number__c;
        d.propertyId = bill.Utility_Account__r.Property__c;
        d.propertyName = bill.Utility_Account__r.Property__r.Display_Name__c;
        d.utilityType = bill.Utility_Account__r.Utility_Type__c;
        d.unitOfMeasure = bill.Utility_Account__r.Unit_Of_Measure__c;
        d.periodStart = bill.Period_Start__c;
        d.periodEnd = bill.Period_End__c;
        d.totalAmount = bill.Total_Amount__c;
        d.totalUnits = bill.Total_Units_Consumed__c;
        d.supplyCharge = bill.Supply_Charge__c;
        d.usageCharge = bill.Usage_Charge__c;
        d.splitMethod = bill.Split_Method__c;
        d.status = bill.Status__c;
        d.calculatedAt = bill.Calculated_At__c;
        d.sentAt = bill.Sent_At__c;
        d.allocatedAmount = bill.Allocated_Amount__c;
        d.variance = bill.Allocation_Variance__c;

        Boolean sent = bill.Status__c == STATUS_SENT;
        d.isLocked = sent && !canReopen();

        Boolean usesSubmeter = bill.Split_Method__c == null
            || bill.Split_Method__c == BillSplitCalculator.METHOD_SUBMETER_RESIDUAL;
        if (usesSubmeter) {
            Meter__c meter = loadSubMeter(bill.Utility_Account__c);
            if (meter != null) {
                d.meter = buildMeterInfo(meter, bill);
                d.needsClosingReading = d.meter.closingId == null;
            }
        }
        d.canEditReading = d.meter != null && !d.isLocked && Schema.sObjectType.Meter_Reading__c.isCreateable();
        d.canCalculate = !d.isLocked && Schema.sObjectType.Utility_Bill__c.isUpdateable()
            && !(usesSubmeter && d.meter != null && d.meter.closingId == null);
        d.canSend = d.status == 'Calculated' && canSend();

        for (Bill_Allocation__c a : [
            SELECT Unit__c, Unit__r.Name, Is_Residual__c, Units_Consumed__c, Usage_Share_Percent__c,
                   Usage_Amount__c, Supply_Amount__c, Total_Amount__c, Calculation_Notes__c
            FROM Bill_Allocation__c WHERE Utility_Bill__c = :billId ORDER BY Unit__r.Name
        ]) {
            AllocationRow r = new AllocationRow();
            r.unitId = a.Unit__c;
            r.unitName = a.Unit__r.Name;
            r.isResidual = a.Is_Residual__c;
            r.unitsConsumed = a.Units_Consumed__c;
            r.sharePercent = a.Usage_Share_Percent__c;
            r.usageAmount = a.Usage_Amount__c;
            r.supplyAmount = a.Supply_Amount__c;
            r.totalAmount = a.Total_Amount__c;
            r.notes = a.Calculation_Notes__c;
            d.allocations.add(r);
        }

        Boolean mayResend = sent && canSend();
        for (Bill_Notification__c n : [
            SELECT Id, Name, Contact__r.Name, Email_Used__c, Delivery_Status__c, Sent_At__c, Error_Message__c
            FROM Bill_Notification__c WHERE Utility_Bill__c = :billId
            ORDER BY CreatedDate DESC, Name DESC
        ]) {
            NotificationRow r = new NotificationRow();
            r.notificationId = n.Id;
            r.reference = n.Name;
            r.contactName = n.Contact__r.Name;
            r.email = n.Email_Used__c;
            r.status = n.Delivery_Status__c;
            r.sentAt = n.Sent_At__c;
            r.message = n.Error_Message__c;
            r.canResend = mayResend && n.Delivery_Status__c == 'Failed';
            d.notifications.add(r);
        }
        return d;
    }

    private static Utility_Bill__c loadBill(Id billId) {
        if (billId == null) {
            throw new BillSplitException('A bill is required.');
        }
        List<Utility_Bill__c> bills = [
            SELECT Id, Bill_Number__c, Status__c, Split_Method__c, Total_Amount__c, Total_Units_Consumed__c,
                   Supply_Charge__c, Usage_Charge__c, Period_Start__c, Period_End__c, Calculated_At__c,
                   Sent_At__c, Allocated_Amount__c, Allocation_Variance__c, Utility_Account__c,
                   Utility_Account__r.Property__c, Utility_Account__r.Property__r.Display_Name__c,
                   Utility_Account__r.Utility_Type__c, Utility_Account__r.Unit_Of_Measure__c
            FROM Utility_Bill__c WHERE Id = :billId
        ];
        if (bills.isEmpty()) {
            throw new BillSplitException('The bill could not be found, or you do not have access to it.');
        }
        return bills[0];
    }

    private static Meter__c loadSubMeter(Id accountId) {
        List<Meter__c> meters = [
            SELECT Id, Name, Unit__c, Unit__r.Name FROM Meter__c
            WHERE Utility_Account__c = :accountId AND Meter_Role__c = 'Sub' AND Active__c = true
            LIMIT 2
        ];
        if (meters.size() > 1) {
            throw new BillSplitException('This utility account has more than one active sub-meter. Only one is supported.');
        }
        return meters.isEmpty() ? null : meters[0];
    }

    private static MeterInfo buildMeterInfo(Meter__c meter, Utility_Bill__c bill) {
        MeterInfo m = new MeterInfo();
        m.meterId = meter.Id;
        m.meterName = meter.Name;
        m.unitName = meter.Unit__r.Name;

        Id meterId = meter.Id;
        Id billId = bill.Id;
        List<Meter_Reading__c> closings = [
            SELECT Id, Reading_Date__c, Reading_Value__c FROM Meter_Reading__c
            WHERE Meter__c = :meterId AND Utility_Bill__c = :billId AND Reading_Type__c = :TYPE_CLOSE
            ORDER BY Reading_Date__c DESC LIMIT 1
        ];
        Meter_Reading__c closing = closings.isEmpty() ? null : closings[0];
        if (closing != null) {
            m.closingId = closing.Id;
            m.closingValue = closing.Reading_Value__c;
            m.closingDate = closing.Reading_Date__c;
        }

        List<Meter_Reading__c> openings;
        if (closing != null) {
            Date closingDate = closing.Reading_Date__c;
            Id closingId = closing.Id;
            openings = [
                SELECT Reading_Date__c, Reading_Value__c FROM Meter_Reading__c
                WHERE Meter__c = :meterId AND Reading_Type__c IN (:TYPE_BASELINE, :TYPE_CLOSE)
                  AND Reading_Date__c < :closingDate AND Id != :closingId
                ORDER BY Reading_Date__c DESC, CreatedDate DESC LIMIT 1
            ];
        } else {
            openings = [
                SELECT Reading_Date__c, Reading_Value__c FROM Meter_Reading__c
                WHERE Meter__c = :meterId AND Reading_Type__c IN (:TYPE_BASELINE, :TYPE_CLOSE)
                ORDER BY Reading_Date__c DESC, CreatedDate DESC LIMIT 1
            ];
        }
        if (!openings.isEmpty()) {
            m.openingValue = openings[0].Reading_Value__c;
            m.openingDate = openings[0].Reading_Date__c;
        }
        return m;
    }

    // ------------------------------------------------------------------ permissions and errors

    private static void requireRead() {
        if (!Schema.sObjectType.Utility_Bill__c.isAccessible()) {
            throw new BillSplitException('You do not have access to bills.');
        }
    }

    private static Boolean canReopen() {
        if (reopenPermissionOverride != null) {
            return reopenPermissionOverride;
        }
        return FeatureManagement.checkPermission('Reopen_Sent_Bill');
    }

    private static void requireSendPermission() {
        if (!canSend()) {
            throw new BillSplitException('You do not have permission to send bills.');
        }
    }

    private static Boolean canSend() {
        if (sendPermissionOverride != null) {
            return sendPermissionOverride;
        }
        return FeatureManagement.checkPermission('Send_Bill_Split');
    }

    private static AuraHandledException toAura(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        String msg = e.getMessage();
        if (e instanceof DmlException) {
            msg = ((DmlException) e).getDmlMessage(0);
        }
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        return ae;
    }
}