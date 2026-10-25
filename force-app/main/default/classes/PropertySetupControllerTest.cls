@isTest
private class PropertySetupControllerTest {

    private static PropertySetupController.Address address(String street) {
        PropertySetupController.Address a = new PropertySetupController.Address();
        a.street = street;
        a.suburb = 'Turner';
        a.state = 'ACT';
        a.postcode = '2612';
        a.latitude = -35.27;
        a.longitude = 149.13;
        a.source = 'Map Pick';
        return a;
    }

    private static PropertySetupController.UnitIn unit(String label, Boolean same, String street) {
        PropertySetupController.UnitIn u = new PropertySetupController.UnitIn();
        u.label = label;
        u.sameAsProperty = same;
        u.status = 'Occupied';
        if (!same) {
            u.address = address(street);
            u.address.source = 'Manual';
        }
        return u;
    }

    private static PropertySetupController.OwnerIn newOwner(String lastName, String email, Integer unitIndex, String pref) {
        PropertySetupController.OwnerIn o = new PropertySetupController.OwnerIn();
        o.newContact = new PropertySetupController.NewContact();
        o.newContact.firstName = 'Pat';
        o.newContact.lastName = lastName;
        o.newContact.email = email;
        o.unitIndex = unitIndex;
        o.role = 'Owner';
        o.preference = pref;
        o.receivesBills = true;
        return o;
    }

    private static PropertySetupController.Payload payload() {
        PropertySetupController.Payload p = new PropertySetupController.Payload();
        p.property = new PropertySetupController.PropertyIn();
        p.property.displayName = '5 Wattle Rd';
        p.property.councilName = 'Test Council';
        p.property.address = address('5 Wattle Rd');
        p.units = new List<PropertySetupController.UnitIn>{
            unit('Unit A', true, null),
            unit('Unit B', false, '5B Wattle Rd')
        };
        p.owners = new List<PropertySetupController.OwnerIn>{
            newOwner('Alpha', 'alpha@example.com', 0, 'Primary'),
            newOwner('Beta', 'beta@example.com', 1, 'Primary')
        };
        p.utility = new PropertySetupController.UtilityIn();
        p.utility.utilityType = 'Water';
        p.utility.provider = 'Test Council';
        p.utility.accountNumber = 'WAT-777';
        p.utility.billingFrequency = 'Quarterly';
        p.utility.unitOfMeasure = 'kL';
        p.utility.hasSubMeter = true;
        p.utility.meterName = 'SUB-777';
        p.utility.meterUnitIndex = 1;
        p.utility.baselineValue = 500;
        p.utility.baselineDate = Date.today().addDays(-30);
        return p;
    }

    private static void assertSaveFails(PropertySetupController.Payload p, String fragment) {
        try {
            PropertySetupController.save(JSON.serialize(p));
            System.assert(false, 'Expected an error containing "' + fragment + '"');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(fragment), 'Unexpected message: ' + e.getMessage());
        }
    }

    @isTest
    static void savesTheWholeSetupInOneGo() {
        PropertySetupController.SaveResult r = PropertySetupController.save(JSON.serialize(payload()));

        System.assertNotEquals(null, r.propertyId);
        System.assertEquals(2, r.unitCount);
        System.assertEquals(2, r.ownerCount);
        System.assertEquals(2, r.newContactCount);

        Property__c prop = [
            SELECT Display_Name__c, Street__c, Address_Source__c, Location__Latitude__s FROM Property__c WHERE Id = :r.propertyId
        ];
        System.assertEquals('Map Pick', prop.Address_Source__c);
        System.assertNotEquals(null, prop.Location__Latitude__s);

        Map<String, Unit__c> units = new Map<String, Unit__c>();
        for (Unit__c u : [SELECT Name, Street__c, Address_Source__c FROM Unit__c WHERE Property__c = :r.propertyId]) {
            units.put(u.Name, u);
        }
        System.assertEquals(2, units.size());
        System.assertEquals('5 Wattle Rd', units.get('Unit A').Street__c, 'Unit A copies the property address');
        System.assertEquals('5B Wattle Rd', units.get('Unit B').Street__c);
        System.assertEquals('Manual', units.get('Unit B').Address_Source__c);

        System.assertEquals(2, [SELECT COUNT() FROM Ownership__c WHERE Property__c = :r.propertyId]);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'Alpha household']);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Name = 'Beta household']);
        System.assertEquals(0, r.warnings.size());
        Map<String, Id> accountByContact = new Map<String, Id>();
        for (Contact c : [SELECT LastName, AccountId FROM Contact WHERE Id IN (SELECT Contact__c FROM Ownership__c WHERE Property__c = :r.propertyId)]) {
            accountByContact.put(c.LastName, c.AccountId);
        }
        System.assertNotEquals(null, accountByContact.get('Alpha'));
        System.assertNotEquals(accountByContact.get('Alpha'), accountByContact.get('Beta'), 'Each new owner has their own account');

        Meter__c meter = [SELECT Name, Unit__r.Name, Meter_Role__c FROM Meter__c WHERE Id = :r.meterId];
        System.assertEquals('SUB-777', meter.Name);
        System.assertEquals('Unit B', meter.Unit__r.Name);
        System.assertEquals(1, [SELECT COUNT() FROM Meter_Reading__c WHERE Meter__c = :r.meterId AND Reading_Type__c = 'Baseline']);
    }

    @isTest
    static void usesAnExistingContactWithoutCreatingOne() {
        Contact existing = BillSplitTestData.contact('Existing', 'existing@example.com', null);
        PropertySetupController.Payload p = payload();
        PropertySetupController.OwnerIn o = new PropertySetupController.OwnerIn();
        o.contactId = existing.Id;
        o.unitIndex = null;
        o.role = 'Owner';
        o.preference = 'Primary';
        o.receivesBills = true;
        p.owners = new List<PropertySetupController.OwnerIn>{ o };

        PropertySetupController.SaveResult r = PropertySetupController.save(JSON.serialize(p));

        System.assertEquals(0, r.newContactCount);
        System.assertEquals(1, r.warnings.size(), 'The existing contact has no account');
        System.assert(r.warnings[0].contains('Existing'), r.warnings[0]);
        Ownership__c own = [SELECT Contact__c, Unit__c FROM Ownership__c WHERE Property__c = :r.propertyId];
        System.assertEquals(existing.Id, own.Contact__c);
        System.assertEquals(null, own.Unit__c, 'Property-wide ownership');
    }

    @isTest
    static void noWarningWhenAnExistingContactHasAnAccount() {
        Account acc = new Account(Name = 'Existing household');
        insert acc;
        Contact existing = new Contact(LastName = 'Housed', Email = 'housed@example.com', AccountId = acc.Id);
        insert existing;
        PropertySetupController.Payload p = payload();
        PropertySetupController.OwnerIn o = new PropertySetupController.OwnerIn();
        o.contactId = existing.Id;
        o.role = 'Owner';
        o.preference = 'Primary';
        o.receivesBills = true;
        p.owners = new List<PropertySetupController.OwnerIn>{ o };

        PropertySetupController.SaveResult r = PropertySetupController.save(JSON.serialize(p));

        System.assertEquals(0, r.warnings.size());
        System.assertEquals(1, [SELECT COUNT() FROM Account], 'No extra account was created');
    }

    @isTest
    static void savesWithoutASubMeter() {
        PropertySetupController.Payload p = payload();
        p.utility.hasSubMeter = false;

        PropertySetupController.SaveResult r = PropertySetupController.save(JSON.serialize(p));

        System.assertEquals(null, r.meterId);
        System.assertEquals(0, [SELECT COUNT() FROM Meter__c]);
    }

    @isTest
    static void manualAddressClearsTheCoordinates() {
        PropertySetupController.Payload p = payload();
        p.property.address.source = 'Manual';

        PropertySetupController.SaveResult r = PropertySetupController.save(JSON.serialize(p));

        Property__c prop = [SELECT Address_Source__c, Location__Latitude__s FROM Property__c WHERE Id = :r.propertyId];
        System.assertEquals('Manual', prop.Address_Source__c);
        System.assertEquals(null, prop.Location__Latitude__s);
    }

    @isTest
    static void rejectsMissingDetailsBeforeWritingAnything() {
        PropertySetupController.Payload p = payload();
        p.property.displayName = ' ';
        assertSaveFails(p, 'property name');

        p = payload();
        p.units.remove(1);
        assertSaveFails(p, 'exactly 2 units');

        p = payload();
        p.units[1].label = 'unit a';
        assertSaveFails(p, 'different');

        p = payload();
        p.owners = new List<PropertySetupController.OwnerIn>();
        assertSaveFails(p, 'at least one owner');

        p = payload();
        p.owners[0].newContact.email = null;
        assertSaveFails(p, 'email address');

        p = payload();
        p.utility.accountNumber = null;
        assertSaveFails(p, 'account number');

        p = payload();
        p.utility.baselineValue = null;
        assertSaveFails(p, 'baseline reading');

        System.assertEquals(0, [SELECT COUNT() FROM Property__c]);
    }

    @isTest
    static void rollsBackEverythingWhenALaterStepFails() {
        PropertySetupController.Payload p = payload();
        p.owners[0].preference = 'Alternate';   // needs an alternate email on the contact, so the Ownership trigger rejects it
        assertSaveFails(p, 'Alternate');

        System.assertEquals(0, [SELECT COUNT() FROM Property__c], 'Property must be rolled back');
        System.assertEquals(0, [SELECT COUNT() FROM Unit__c], 'Units must be rolled back');
        System.assertEquals(0, [SELECT COUNT() FROM Contact], 'Contacts must be rolled back');
    }

    @isTest
    static void rejectsUnreadablePayload() {
        try {
            PropertySetupController.save('{not json');
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('could not be read'));
        }
    }
}