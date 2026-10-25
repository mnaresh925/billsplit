@isTest
private class BillSplitControllerSendTest {

    private static BillSplitTestData.Scenario calculatedBillWithOwners() {
        BillSplitTestData.Scenario s = BillSplitTestData.scenario();
        Contact alpha = BillSplitTestData.contact('Alpha', 'alpha@example.com', null);
        Contact beta = BillSplitTestData.contact('Beta', 'beta@example.com', 'beta.billing@example.com');
        insert new List<Ownership__c>{
            BillSplitTestData.ownershipRecord(s.property.Id, alpha.Id, s.unitA.Id, 'Primary'),
            BillSplitTestData.ownershipRecord(s.property.Id, beta.Id, s.unitB.Id, 'Both')
        };
        BillSplitController.calculate(s.bill.Id);
        return s;
    }

    @isTest
    static void sendRequiresThePermission() {
        BillSplitTestData.Scenario s = calculatedBillWithOwners();
        BillSplitController.sendPermissionOverride = false;

        try {
            BillSplitController.sendBill(s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assertEquals('You do not have permission to send bills.', e.getMessage());
        }
        try {
            BillSplitController.getSendPreview(s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assertEquals('You do not have permission to send bills.', e.getMessage());
        }
        System.assertEquals(0, [SELECT COUNT() FROM Bill_Notification__c]);
    }

    @isTest
    static void previewThenSendUpdatesTheWorkbench() {
        BillSplitTestData.Scenario s = calculatedBillWithOwners();
        BillSplitController.sendPermissionOverride = true;

        BillSplitNotificationService.Preview p = BillSplitController.getSendPreview(s.bill.Id);
        System.assertEquals(3, p.recipients.size());
        System.assertEquals(0, p.blockers.size());

        BillSplitController.WorkbenchData d = BillSplitController.sendBill(s.bill.Id);

        System.assertEquals('Sent', d.status);
        System.assertEquals(3, d.notifications.size());
        System.assertEquals(false, d.canSend, 'Already sent');
        for (BillSplitController.NotificationRow n : d.notifications) {
            System.assertEquals('Sent', n.status);
            System.assertEquals(false, n.canResend);
        }
    }

    @isTest
    static void failedRowsOfASentBillOfferResend() {
        BillSplitTestData.Scenario s = calculatedBillWithOwners();
        BillSplitController.sendPermissionOverride = true;
        BillSplitController.reopenPermissionOverride = false;
        BillSplitController.sendBill(s.bill.Id);
        Bill_Notification__c row = [SELECT Id FROM Bill_Notification__c WHERE Utility_Bill__c = :s.bill.Id LIMIT 1];
        update new Bill_Notification__c(Id = row.Id, Delivery_Status__c = 'Failed', Error_Message__c = 'Bounced');

        BillSplitController.WorkbenchData d = BillSplitController.getWorkbench(s.bill.Id);
        Integer resendable = 0;
        for (BillSplitController.NotificationRow n : d.notifications) {
            if (n.canResend) {
                resendable++;
            }
        }
        System.assertEquals(1, resendable);

        d = BillSplitController.resendNotification(s.bill.Id, row.Id);

        System.assertEquals('Sent', d.status, 'Resend does not change the bill status');
        for (BillSplitController.NotificationRow n : d.notifications) {
            System.assertEquals('Sent', n.status);
        }
    }

    @isTest
    static void resendRejectsANotificationFromAnotherBill() {
        BillSplitTestData.Scenario s = calculatedBillWithOwners();
        BillSplitController.sendPermissionOverride = true;
        Bill_Notification__c stray = new Bill_Notification__c(
            Utility_Bill__c = s.bill.Id, Contact__c = [SELECT Id FROM Contact LIMIT 1].Id,
            Email_Used__c = 'x@example.com', Delivery_Status__c = 'Failed'
        );
        insert stray;
        BillSplitTestData.Scenario other = BillSplitTestData.scenario();

        try {
            BillSplitController.resendNotification(other.bill.Id, stray.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('does not belong'), e.getMessage());
        }
    }

    @isTest
    static void sendFailuresComeBackAsWarningsAndTheBillStaysCalculated() {
        BillSplitTestData.Scenario s = calculatedBillWithOwners();
        BillSplitController.sendPermissionOverride = true;
        BillSplitNotificationService.forcedFailureMessage = 'Mailbox full';

        BillSplitController.WorkbenchData d = BillSplitController.sendBill(s.bill.Id);

        System.assertEquals('Calculated', d.status);
        System.assertEquals(3, d.notifications.size());
        System.assert(!d.warnings.isEmpty());
        System.assertEquals(true, d.canSend, 'The user can try again');
    }
}