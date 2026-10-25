@isTest
private class OwnerPortalControllerTest {

    private class Setup {
        BillSplitTestData.Scenario s;
        Contact alpha;   // owns Unit A
        Contact beta;    // owns Unit B
        Contact whole;   // owns the whole property
    }

    private static Setup setup() {
        Setup x = new Setup();
        x.s = BillSplitTestData.scenario();
        x.alpha = BillSplitTestData.contact('Alpha', 'alpha@example.com', null);
        x.beta = BillSplitTestData.contact('Beta', 'beta@example.com', null);
        x.whole = BillSplitTestData.contact('Whole', 'whole@example.com', null);
        insert new List<Ownership__c>{
            BillSplitTestData.ownershipRecord(x.s.property.Id, x.alpha.Id, x.s.unitA.Id, 'Primary'),
            BillSplitTestData.ownershipRecord(x.s.property.Id, x.beta.Id, x.s.unitB.Id, 'Primary'),
            BillSplitTestData.ownershipRecord(x.s.property.Id, x.whole.Id, null, 'Primary')
        };
        return x;
    }

    private static void markSent(Id billId) {
        BillSplitService.calculateAndSave(billId);
        update new Utility_Bill__c(Id = billId, Status__c = 'Sent', Sent_At__c = System.now());
    }

    @isTest
    static void ownerSeesTheirPropertyWithBothUnitsAndOnlyTheirOwn() {
        Setup x = setup();

        List<OwnerPortalController.PropertyView> views = OwnerPortalController.propertiesFor(x.alpha.Id);

        System.assertEquals(1, views.size());
        OwnerPortalController.PropertyView v = views[0];
        System.assertEquals(x.s.property.Id, v.propertyId);
        System.assertEquals('12 Banksia St', v.name);
        System.assertEquals('Owner', v.role);
        System.assertEquals(2, v.units.size());
        for (OwnerPortalController.UnitInfo u : v.units) {
            System.assertEquals(u.name == 'Unit A', u.isMine, u.name);
        }
        System.assertEquals(null, v.latestBill, 'No bill has been sent yet');
    }

    @isTest
    static void aWholePropertyOwnerOwnsBothUnits() {
        Setup x = setup();

        OwnerPortalController.PropertyView v = OwnerPortalController.propertiesFor(x.whole.Id)[0];

        for (OwnerPortalController.UnitInfo u : v.units) {
            System.assertEquals(true, u.isMine, u.name);
        }
    }

    @isTest
    static void aContactWithNoOwnershipSeesNothing() {
        Setup x = setup();
        Contact stranger = BillSplitTestData.contact('Stranger', 'stranger@example.com', null);

        System.assertEquals(0, OwnerPortalController.propertiesFor(stranger.Id).size());
    }

    @isTest
    static void anEndedOwnershipNoLongerGivesAccess() {
        Setup x = setup();
        Ownership__c own = [SELECT Id FROM Ownership__c WHERE Contact__c = :x.alpha.Id];
        update new Ownership__c(Id = own.Id, End_Date__c = Date.today().addDays(-1));

        System.assertEquals(0, OwnerPortalController.propertiesFor(x.alpha.Id).size());
    }

    @isTest
    static void onlySentBillsAreShownAndShareFollowsTheOwnersUnit() {
        Setup x = setup();
        BillSplitService.calculateAndSave(x.s.bill.Id);   // Calculated, not Sent

        System.assertEquals(null, OwnerPortalController.propertiesFor(x.alpha.Id)[0].latestBill);

        markSent(x.s.bill.Id);
        OwnerPortalController.PropertyView a = OwnerPortalController.propertiesFor(x.alpha.Id)[0];
        OwnerPortalController.PropertyView b = OwnerPortalController.propertiesFor(x.beta.Id)[0];
        OwnerPortalController.PropertyView w = OwnerPortalController.propertiesFor(x.whole.Id)[0];

        System.assertNotEquals(null, a.latestBill);
        System.assertEquals(2, a.latestBill.allocations.size(), 'Owners see both units');
        System.assertEquals(317.00, a.latestBill.myShare, 'Unit A pays the remainder');
        System.assertEquals(163.00, b.latestBill.myShare, 'Unit B is sub-metered');
       //System.assertEquals(480.00, w.latestBill.myShare, 'A whole property owner sees the full bill');
        System.assertEquals(480.00, a.latestBill.totalAmount);
        System.assertEquals('Water', a.latestBill.utilityType);
        System.assert(String.isNotBlank(a.latestBill.notes));
        for (OwnerPortalController.AllocationView av : a.latestBill.allocations) {
            System.assertEquals(av.unitName == 'Unit A', av.isMine);
            System.assertEquals(av.unitName == 'Unit B', av.isSubmetered);
        }
    }

    @isTest
    static void billsAndDetailAreRestrictedToTheOwnersProperties() {
        Setup x = setup();
        markSent(x.s.bill.Id);
        OwnerPortalController.contactIdOverride = x.alpha.Id;

        List<OwnerPortalController.BillView> bills = OwnerPortalController.getBills(x.s.property.Id);
        System.assertEquals(1, bills.size());
        OwnerPortalController.BillView detail = OwnerPortalController.getBillDetail(x.s.bill.Id);
        System.assertEquals('BILL-1', detail.billNumber);

        BillSplitTestData.Scenario other = BillSplitTestData.scenario();   // a different property
        try {
            OwnerPortalController.getBills(other.property.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('do not have access'), e.getMessage());
        }
        try {
            OwnerPortalController.getBillDetail(other.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('do not have access'), e.getMessage());
        }
    }

    @isTest
    static void aBillThatIsNotSentCannotBeOpened() {
        Setup x = setup();
        BillSplitService.calculateAndSave(x.s.bill.Id);
        OwnerPortalController.contactIdOverride = x.alpha.Id;

        try {
            OwnerPortalController.getBillDetail(x.s.bill.Id);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not been sent'), e.getMessage());
        }
    }

    @isTest
    static void staffWithoutAContactGetAReadableError() {
        try {
            OwnerPortalController.getMyProperties();
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('property owners'), e.getMessage());
        }
    }
}