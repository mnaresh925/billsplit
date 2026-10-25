/**
 * Works out who receives a bill split, sends one email per address, and records the outcome as
 * Bill_Notification__c rows. Runs with sharing; field access is system mode because staff only have read
 * access to notifications. The controller checks the Send_Bill_Split permission before calling.
 *
 * One email goes to each distinct address. A contact set to "Both" gets two emails, one per address,
 * so each outcome is logged on its own row.
 */
public with sharing class BillSplitNotificationService {

    private static final String STATUS_CALCULATED = 'Calculated';
    private static final String STATUS_SENT = 'Sent';

    /** Test seam: when set, every send is treated as failed with this message. */
    @TestVisible private static String forcedFailureMessage;

    public class Recipient {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String firstName;
        @AuraEnabled public String email;
        @AuraEnabled public String note;
    }

    public class Preview {
        @AuraEnabled public List<Recipient> recipients = new List<Recipient>();
        @AuraEnabled public List<String> blockers = new List<String>();
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public String subject;
        @AuraEnabled public String senderName;
    }

    public class SendResult {
        @AuraEnabled public Integer sent = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public List<String> messages = new List<String>();
    }

    private class Data {
        Utility_Bill__c bill;
        String propertyName;
        String utilityType;
        String unitOfMeasure;
        List<Bill_Allocation__c> allocations = new List<Bill_Allocation__c>();
    }

    // ------------------------------------------------------------------ public API

    /** Shows who would receive the email and why a send would be refused. Never sends or writes. */
    public static Preview preview(Id billId) {
        Data d = load(billId);
        Preview p = new Preview();
        p.blockers = blockers(d);
        resolveRecipients(d, p);
        if (p.recipients.isEmpty() && p.blockers.isEmpty()) {
            p.blockers.add('No active owner is set to receive bills. Check the ownership records for this property.');
        }
        p.subject = BillSplitEmailBuilder.build(model(d, null)).subject;
        String name = BillSplitSettings.orgWideEmailName();
        if (String.isBlank(name)) {
            p.senderName = UserInfo.getName() + ' (your own address)';
            p.warnings.add('No Org-Wide Email Address is configured, so emails will come from your own address.');
        } else {
            p.senderName = name;
        }
        return p;
    }

    /** Sends the split to every recipient. Throws BillSplitException when the bill cannot be sent. */
    public static SendResult send(Id billId) {
        lock(billId);
        Data d = load(billId);
        List<String> problems = blockers(d);
        Preview p = new Preview();
        resolveRecipients(d, p);
        if (p.recipients.isEmpty() && problems.isEmpty()) {
            problems.add('No active owner is set to receive bills.');
        }
        if (!problems.isEmpty()) {
            throw new BillSplitException(String.join(problems, ' '));
        }

        OrgWideEmailAddress sender = findSender();
        String batchId = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        List<Bill_Notification__c> rows = new List<Bill_Notification__c>();
        for (Recipient r : p.recipients) {
            messages.add(buildMessage(d, r, sender));
            rows.add(new Bill_Notification__c(
                Utility_Bill__c = billId, Contact__c = r.contactId, Email_Used__c = r.email,
                Send_Batch_Id__c = batchId, Error_Message__c = trim255(r.note)
            ));
        }

        List<Boolean> outcome = new List<Boolean>();
        List<String> errors = new List<String>();
        dispatch(messages, outcome, errors);

        SendResult result = new SendResult();
        result.messages.addAll(p.warnings);
        for (Integer i = 0; i < rows.size(); i++) {
            Bill_Notification__c row = rows[i];
            if (outcome[i]) {
                row.Delivery_Status__c = 'Sent';
                row.Sent_At__c = System.now();
                result.sent++;
            } else {
                row.Delivery_Status__c = 'Failed';
                row.Error_Message__c = trim255(errors[i]);
                result.failed++;
                result.messages.add('Could not send to ' + row.Email_Used__c + ': ' + errors[i]);
            }
        }
        insert rows;
        if (result.sent > 0) {
            update new Utility_Bill__c(Id = billId, Status__c = STATUS_SENT, Sent_At__c = System.now());
        }
        return result;
    }

    /**
     * Sends one failed notification again. Does not change the bill status. Returns null on success or the
     * failure message, so the failed attempt can still be logged on the row (an exception would roll it back).
     */
    public static String resend(Id notificationId) {
        List<Bill_Notification__c> found = [
            SELECT Id, Utility_Bill__c, Contact__c, Contact__r.FirstName, Email_Used__c, Delivery_Status__c
            FROM Bill_Notification__c WHERE Id = :notificationId FOR UPDATE
        ];
        if (found.isEmpty()) {
            throw new BillSplitException('The notification could not be found.');
        }
        Bill_Notification__c row = found[0];
        if (row.Delivery_Status__c != 'Failed') {
            throw new BillSplitException('Only failed notifications can be sent again.');
        }
        Data d = load(row.Utility_Bill__c);
        if (d.bill.Status__c != STATUS_SENT) {
            throw new BillSplitException('The bill has not been sent. Use Send instead of Resend.');
        }
        if (d.allocations.size() != 2) {
            throw new BillSplitException('The split for this bill is missing. Recalculate it first.');
        }
        Recipient r = new Recipient();
        r.contactId = row.Contact__c;
        r.firstName = row.Contact__r.FirstName;
        r.email = row.Email_Used__c;

        List<Boolean> outcome = new List<Boolean>();
        List<String> errors = new List<String>();
        dispatch(new List<Messaging.SingleEmailMessage>{ buildMessage(d, r, findSender()) }, outcome, errors);

        if (outcome[0]) {
            row.Delivery_Status__c = 'Sent';
            row.Sent_At__c = System.now();
            row.Error_Message__c = null;
        } else {
            row.Error_Message__c = trim255(errors[0]);
        }
        update row;
        return outcome[0] ? null : 'Could not send to ' + r.email + ': ' + errors[0];
    }

    // ------------------------------------------------------------------ loading and rules

    private static void lock(Id billId) {
        if (billId == null) {
            throw new BillSplitException('A bill is required.');
        }
        List<Utility_Bill__c> locked = [SELECT Id FROM Utility_Bill__c WHERE Id = :billId FOR UPDATE];
        if (locked.isEmpty()) {
            throw new BillSplitException('The bill could not be found, or you do not have access to it.');
        }
    }

    private static Data load(Id billId) {
        if (billId == null) {
            throw new BillSplitException('A bill is required.');
        }
        List<Utility_Bill__c> bills = [
            SELECT Id, Bill_Number__c, Status__c, Total_Amount__c, Total_Units_Consumed__c, Supply_Charge__c,
                   Period_Start__c, Period_End__c, Due_Date__c, Allocation_Variance__c, Utility_Account__c,
                   Utility_Account__r.Property__c, Utility_Account__r.Property__r.Display_Name__c,
                   Utility_Account__r.Utility_Type__c, Utility_Account__r.Unit_Of_Measure__c
            FROM Utility_Bill__c WHERE Id = :billId
        ];
        if (bills.isEmpty()) {
            throw new BillSplitException('The bill could not be found, or you do not have access to it.');
        }
        Data d = new Data();
        d.bill = bills[0];
        d.propertyName = d.bill.Utility_Account__r.Property__r.Display_Name__c;
        d.utilityType = d.bill.Utility_Account__r.Utility_Type__c;
        d.unitOfMeasure = d.bill.Utility_Account__r.Unit_Of_Measure__c;
        d.allocations = [
            SELECT Unit__c, Unit__r.Name, Is_Residual__c, Units_Consumed__c, Usage_Amount__c, Supply_Amount__c,
                   Total_Amount__c, Calculation_Notes__c, Meter__c
            FROM Bill_Allocation__c WHERE Utility_Bill__c = :billId ORDER BY Unit__r.Name
        ];
        return d;
    }

    private static List<String> blockers(Data d) {
        List<String> list1 = new List<String>();
        if (d.bill.Status__c == STATUS_SENT) {
            list1.add('This bill has already been sent. Resend failed emails, or reopen the bill to send it again.');
        } else if (d.bill.Status__c != STATUS_CALCULATED) {
            list1.add('Calculate the split before sending.');
        }
        if (d.bill.Status__c == STATUS_CALCULATED) {
            if (d.allocations.size() != 2) {
                list1.add('The split is incomplete. Recalculate it.');
            }
            Decimal variance = d.bill.Allocation_Variance__c;
            if (variance == null || variance != 0) {
                list1.add('The shares do not add up to the bill total, so it cannot be sent.');
            }
        }
        return list1;
    }

    private static void resolveRecipients(Data d, Preview p) {
        Id propertyId = d.bill.Utility_Account__r.Property__c;
        List<Ownership__c> owners = [
            SELECT Contact__c, Contact__r.FirstName, Contact__r.LastName, Contact__r.Name, Contact__r.Email,
                   Contact__r.Alternate_Billing_Email__c, Bill_Email_Preference__c
            FROM Ownership__c
            WHERE Property__c = :propertyId AND Receives_Bills__c = true AND Is_Active__c = true
            ORDER BY Contact__r.LastName, Contact__r.FirstName
        ];
        Set<String> seen = new Set<String>();
        Set<Id> reportedMissing = new Set<Id>();
        for (Ownership__c o : owners) {
            Contact c = o.Contact__r;
            String primary = clean(c.Email);
            String alternate = clean(c.Alternate_Billing_Email__c);
            String pref = o.Bill_Email_Preference__c;
            List<String> addresses = new List<String>();
            String note;
            if (pref == 'Alternate') {
                if (alternate != null) {
                    addresses.add(alternate);
                } else if (primary != null) {
                    addresses.add(primary);
                    note = 'The alternate email was blank, so the primary email was used.';
                }
            } else if (pref == 'Both') {
                if (primary != null) {
                    addresses.add(primary);
                }
                if (alternate != null) {
                    addresses.add(alternate);
                }
            } else if (primary != null) {
                addresses.add(primary);
            }
            if (addresses.isEmpty()) {
                if (reportedMissing.add(c.Id)) {
                    p.warnings.add(c.Name + ' has no usable email address and will be skipped.');
                }
                continue;
            }
            for (String address : addresses) {
                if (!seen.add(address.toLowerCase())) {
                    continue;
                }
                Recipient r = new Recipient();
                r.contactId = c.Id;
                r.contactName = c.Name;
                r.firstName = c.FirstName;
                r.email = address;
                r.note = note;
                p.recipients.add(r);
                if (note != null) {
                    p.warnings.add(c.Name + ': ' + note);
                }
            }
        }
    }

    private static String clean(String email) {
        return String.isBlank(email) ? null : email.trim();
    }

    // ------------------------------------------------------------------ message building and sending

    private static BillSplitEmailBuilder.Model model(Data d, Recipient r) {
        BillSplitEmailBuilder.Model m = new BillSplitEmailBuilder.Model();
        m.recipientFirstName = r == null ? null : r.firstName;
        m.utilityType = d.utilityType;
        m.propertyName = d.propertyName;
        m.billNumber = d.bill.Bill_Number__c;
        m.periodStart = d.bill.Period_Start__c;
        m.periodEnd = d.bill.Period_End__c;
        m.dueDate = d.bill.Due_Date__c;
        m.totalUnits = d.bill.Total_Units_Consumed__c;
        m.unitOfMeasure = d.unitOfMeasure;
        m.totalAmount = d.bill.Total_Amount__c;
        m.supplyCharge = d.bill.Supply_Charge__c;
        m.footer = BillSplitSettings.emailFooter();
        for (Bill_Allocation__c a : d.allocations) {
            BillSplitEmailBuilder.UnitRow row = new BillSplitEmailBuilder.UnitRow();
            row.unitName = a.Unit__r.Name;
            row.isSubmetered = a.Meter__c != null;
            row.unitsConsumed = a.Units_Consumed__c;
            row.usageAmount = a.Usage_Amount__c;
            row.supplyAmount = a.Supply_Amount__c;
            row.totalAmount = a.Total_Amount__c;
            m.rows.add(row);
            if (m.methodText == null && String.isNotBlank(a.Calculation_Notes__c)) {
                m.methodText = a.Calculation_Notes__c;
            }
        }
        return m;
    }

    private static Messaging.SingleEmailMessage buildMessage(Data d, Recipient r, OrgWideEmailAddress sender) {
        BillSplitEmailBuilder.Email e = BillSplitEmailBuilder.build(model(d, r));
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ r.email });
        msg.setSubject(e.subject);
        msg.setHtmlBody(e.htmlBody);
        msg.setPlainTextBody(e.plainBody);
        msg.setSaveAsActivity(false);
        if (sender != null) {
            msg.setOrgWideEmailAddressId(sender.Id);
            msg.setReplyTo(sender.Address);
        }
        return msg;
    }

    private static OrgWideEmailAddress findSender() {
        String name = BillSplitSettings.orgWideEmailName();
        if (String.isBlank(name)) {
            return null;
        }
        List<OrgWideEmailAddress> found = [SELECT Id, Address FROM OrgWideEmailAddress WHERE DisplayName = :name LIMIT 1];
        if (found.isEmpty()) {
            throw new BillSplitException('The Org-Wide Email Address "' + name
                + '" was not found. Check the Default record of Bill Split Setting and the address in Setup.');
        }
        return found[0];
    }

    /** Sends all messages without stopping on the first failure and fills one outcome and error per message. */
    private static void dispatch(List<Messaging.SingleEmailMessage> messages, List<Boolean> outcome, List<String> errors) {
        if (forcedFailureMessage != null) {
            for (Integer i = 0; i < messages.size(); i++) {
                outcome.add(false);
                errors.add(forcedFailureMessage);
            }
            return;
        }
        try {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);
            for (Messaging.SendEmailResult r : results) {
                if (r.isSuccess()) {
                    outcome.add(true);
                    errors.add(null);
                } else {
                    outcome.add(false);
                    errors.add(r.getErrors().isEmpty() ? 'The email was not accepted.' : r.getErrors()[0].getMessage());
                }
            }
        } catch (EmailException e) {
            outcome.clear();
            errors.clear();
            for (Integer i = 0; i < messages.size(); i++) {
                outcome.add(false);
                errors.add(e.getMessage());
            }
        }
    }

    private static String trim255(String s) {
        return s == null ? null : (s.length() > 255 ? s.substring(0, 255) : s);
    }
}