@isTest
private class BillSplitNotificationServiceTest {

    private class Setup {
        BillSplitTestData.Scenario s;
        Contact alpha;
        Contact beta;
    }

    /** Alpha owns Unit A (primary email). Beta owns Unit B (both emails). That is three addresses. */
    private static Setup twoOwners() {
        Setup x = new Setup();
        x.s = BillSplitTestData.scenario();
        x.alpha = BillSplitTestData.contact('Alpha', 'alpha@example.com', null);
        x.beta = BillSplitTestData.contact('Beta', 'beta@example.com', 'beta.billing@example.com');
        insert new List<Ownership__c>{
            BillSplitTestData.ownershipRecord(x.s.property.Id, x.alpha.Id, x.s.unitA.Id, 'Primary'),
            BillSplitTestData.ownershipRecord(x.s.property.Id, x.beta.Id, x.s.unitB.Id, 'Both')
        };
        return x;
    }

    private static Set<String> addresses(List<BillSplitNotificationService.Recipient> recipients) {
        Set<String> out = new Set<String>();
        for (BillSplitNotificationService.Recipient r : recipients) {
            out.add(r.email);
        }
        return out;
    }

    @isTest
    static void previewBlocksADraftBill() {
        Setup x = twoOwners();

        BillSplitNotificationService.Preview p = BillSplitNotificationService.preview(x.s.bill.Id);

        System.assertEquals(1, p.blockers.size());
        System.assert(p.blockers[0].contains('Calculate the split'));
    }

    @isTest
    static void previewListsOneRecipientPerAddress() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);

        BillSplitNotificationService.Preview p = BillSplitNotificationService.preview(x.s.bill.Id);

        System.assertEquals(0, p.blockers.size(), String.join(p.blockers, ' '));
        System.assertEquals(3, p.recipients.size());
        System.assertEquals(
            new Set<String>{ 'alpha@example.com', 'beta@example.com', 'beta.billing@example.com' },
            addresses(p.recipients)
        );
        System.assert(p.subject.startsWith('Water bill split for 12 Banksia St'));
        System.assert(p.senderName.contains('your own address'), 'No org-wide address is configured in tests');
    }

    @isTest
    static void sendEmailsEachAddressAndMarksTheBillSent() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);

        Test.startTest();
        BillSplitNotificationService.SendResult r = BillSplitNotificationService.send(x.s.bill.Id);
        System.assertEquals(1, Limits.getEmailInvocations(), 'All messages go in one send call');
        Test.stopTest();

        System.assertEquals(3, r.sent);
        System.assertEquals(0, r.failed);
        List<Bill_Notification__c> rows = [
            SELECT Contact__c, Email_Used__c, Delivery_Status__c, Sent_At__c, Send_Batch_Id__c
            FROM Bill_Notification__c WHERE Utility_Bill__c = :x.s.bill.Id
        ];
        System.assertEquals(3, rows.size());
        Set<String> batches = new Set<String>();
        for (Bill_Notification__c n : rows) {
            System.assertEquals('Sent', n.Delivery_Status__c);
            System.assertNotEquals(null, n.Sent_At__c);
            batches.add(n.Send_Batch_Id__c);
        }
        System.assertEquals(1, batches.size(), 'One batch id for the whole send');
        Utility_Bill__c bill = [SELECT Status__c, Sent_At__c FROM Utility_Bill__c WHERE Id = :x.s.bill.Id];
        System.assertEquals('Sent', bill.Status__c);
        System.assertNotEquals(null, bill.Sent_At__c);
    }

    @isTest
    static void aContactWhoOwnsBothUnitsGetsOneEmail() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Contact c = BillSplitTestData.contact('Solo', 'solo@example.com', null);
        insert new List<Ownership__c>{
            BillSplitTestData.ownershipRecord(s.property.Id, c.Id, s.unitA.Id, 'Primary'),
            BillSplitTestData.ownershipRecord(s.property.Id, c.Id, s.unitB.Id, 'Primary')
        };
        BillSplitService.calculateAndSave(s.bill.Id);

        BillSplitNotificationService.Preview p = BillSplitNotificationService.preview(s.bill.Id);

        System.assertEquals(1, p.recipients.size());
        System.assertEquals('solo@example.com', p.recipients[0].email);
    }

    @isTest
    static void aSentBillCannotBeSentTwice() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        BillSplitNotificationService.send(x.s.bill.Id);

        try {
            BillSplitNotificationService.send(x.s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (BillSplitException e) {
            System.assert(e.getMessage().contains('already been sent'), e.getMessage());
        }
        System.assertEquals(3, [SELECT COUNT() FROM Bill_Notification__c WHERE Utility_Bill__c = :x.s.bill.Id]);
    }

    @isTest
    static void aDraftBillCannotBeSent() {
        Setup x = twoOwners();
        try {
            BillSplitNotificationService.send(x.s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (BillSplitException e) {
            System.assert(e.getMessage().contains('Calculate the split'), e.getMessage());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Bill_Notification__c]);
    }

    @isTest
    static void aBillWithAVarianceCannotBeSent() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        Bill_Allocation__c a = [SELECT Id, Total_Amount__c FROM Bill_Allocation__c WHERE Utility_Bill__c = :x.s.bill.Id LIMIT 1];
        update new Bill_Allocation__c(Id = a.Id, Total_Amount__c = a.Total_Amount__c + 1);

        BillSplitNotificationService.Preview p = BillSplitNotificationService.preview(x.s.bill.Id);

        System.assert(!p.blockers.isEmpty());
        System.assert(p.blockers[0].contains('do not add up'), p.blockers[0]);
    }

    @isTest
    static void aBillWithNoRecipientsCannotBeSent() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        BillSplitService.calculateAndSave(s.bill.Id);

        BillSplitNotificationService.Preview p = BillSplitNotificationService.preview(s.bill.Id);

        System.assertEquals(0, p.recipients.size());
        System.assert(p.blockers[0].contains('No active owner'));
    }

    @isTest
    static void usesThePrimaryEmailWhenTheAlternateHasGoneBlank() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Contact c = BillSplitTestData.contact('Fallback', 'fallback@example.com', 'fallback.billing@example.com');
        insert new List<Ownership__c>{ BillSplitTestData.ownershipRecord(s.property.Id, c.Id, s.unitA.Id, 'Alternate') };
        update new Contact(Id = c.Id, Alternate_Billing_Email__c = null);
        BillSplitService.calculateAndSave(s.bill.Id);

        BillSplitNotificationService.Preview p = BillSplitNotificationService.preview(s.bill.Id);

        System.assertEquals(1, p.recipients.size());
        System.assertEquals('fallback@example.com', p.recipients[0].email);
        System.assert(String.join(p.warnings, ' ').contains('alternate email was blank'));
    }

    @isTest
    static void failedSendsAreLoggedAndTheBillStaysCalculated() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        BillSplitNotificationService.forcedFailureMessage = 'Mailbox full';

        BillSplitNotificationService.SendResult r = BillSplitNotificationService.send(x.s.bill.Id);

        System.assertEquals(0, r.sent);
        System.assertEquals(3, r.failed);
        for (Bill_Notification__c n : [
            SELECT Delivery_Status__c, Error_Message__c FROM Bill_Notification__c WHERE Utility_Bill__c = :x.s.bill.Id
        ]) {
            System.assertEquals('Failed', n.Delivery_Status__c);
            System.assertEquals('Mailbox full', n.Error_Message__c);
        }
        System.assertEquals('Calculated', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :x.s.bill.Id].Status__c);
    }

    @isTest
    static void resendRecoversAFailedRowWithoutChangingTheBill() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        update new Utility_Bill__c(Id = x.s.bill.Id, Status__c = 'Sent', Sent_At__c = System.now());
        Bill_Notification__c failed = new Bill_Notification__c(
            Utility_Bill__c = x.s.bill.Id, Contact__c = x.beta.Id, Email_Used__c = 'beta@example.com',
            Delivery_Status__c = 'Failed', Error_Message__c = 'Bounced'
        );
        insert failed;

        String problem = BillSplitNotificationService.resend(failed.Id);

        System.assertEquals(null, problem);
        Bill_Notification__c row = [SELECT Delivery_Status__c, Error_Message__c, Sent_At__c FROM Bill_Notification__c WHERE Id = :failed.Id];
        System.assertEquals('Sent', row.Delivery_Status__c);
        System.assertEquals(null, row.Error_Message__c);
        System.assertNotEquals(null, row.Sent_At__c);
        System.assertEquals('Sent', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :x.s.bill.Id].Status__c);
    }

    @isTest
    static void aFailedResendKeepsTheRowFailedAndReportsWhy() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        update new Utility_Bill__c(Id = x.s.bill.Id, Status__c = 'Sent', Sent_At__c = System.now());
        Bill_Notification__c failed = new Bill_Notification__c(
            Utility_Bill__c = x.s.bill.Id, Contact__c = x.beta.Id, Email_Used__c = 'beta@example.com',
            Delivery_Status__c = 'Failed', Error_Message__c = 'Bounced'
        );
        insert failed;
        BillSplitNotificationService.forcedFailureMessage = 'Still bouncing';

        String problem = BillSplitNotificationService.resend(failed.Id);

        System.assert(problem.contains('Still bouncing'), problem);
        Bill_Notification__c row = [SELECT Delivery_Status__c, Error_Message__c FROM Bill_Notification__c WHERE Id = :failed.Id];
        System.assertEquals('Failed', row.Delivery_Status__c);
        System.assertEquals('Still bouncing', row.Error_Message__c);
    }

    @isTest
    static void resendRefusesRowsThatAreNotFailed() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        BillSplitNotificationService.send(x.s.bill.Id);
        Bill_Notification__c sent = [SELECT Id FROM Bill_Notification__c WHERE Utility_Bill__c = :x.s.bill.Id LIMIT 1];

        try {
            BillSplitNotificationService.resend(sent.Id);
            System.assert(false, 'Expected an error');
        } catch (BillSplitException e) {
            System.assert(e.getMessage().contains('Only failed'), e.getMessage());
        }
    }

    @isTest
    static void anUnknownOrgWideAddressStopsTheSend() {
        Setup x = twoOwners();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        BillSplitSettings.orgWideNameOverride = 'No Such Sender';
        BillSplitSettings.orgWideNameOverrideSet = true;

        try {
            BillSplitNotificationService.send(x.s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (BillSplitException e) {
            System.assert(e.getMessage().contains('No Such Sender'), e.getMessage());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Bill_Notification__c]);
        System.assertEquals('Calculated', [SELECT Status__c FROM Utility_Bill__c WHERE Id = :x.s.bill.Id].Status__c);
    }
}