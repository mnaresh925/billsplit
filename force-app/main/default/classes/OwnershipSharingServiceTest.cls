@isTest
private class OwnershipSharingServiceTest {

    private class Fixture {
        BillSplitTestData.Scenario s;
        Account account;
        Contact contact;
        User portalUser;
    }

    /** Role for the running user, so a portal account owner has one. Setup objects are kept apart from data DML. */
    private static void giveRunningUserARole() {
        User me = new User(Id = UserInfo.getUserId());
        System.runAs(me) {
            UserRole r = new UserRole(Name = 'Bill Split Test Role', DeveloperName = 'Bill_Split_Test_Role_' + String.valueOf(Crypto.getRandomInteger()).replace('-', 'n'));
            insert r;
            update new User(Id = UserInfo.getUserId(), UserRoleId = r.Id);
        }
    }

    private static Profile portalProfile() {
        List<Profile> p = [SELECT Id FROM Profile WHERE Name = 'Customer Community Plus User' LIMIT 1];
        return p.isEmpty() ? null : p[0];
    }

    private static Fixture fixture() {
        Fixture f = new Fixture();
        giveRunningUserARole();
        f.s = BillSplitTestData.scenario();
        f.account = new Account(Name = 'Portal Test Household', OwnerId = UserInfo.getUserId());
        insert f.account;
        f.contact = new Contact(LastName = 'Portal', Email = 'portal.test@example.com', AccountId = f.account.Id);
        insert f.contact;
        return f;
    }

    private static User createPortalUser(Fixture f, Profile p) {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User u = new User(
            ContactId = f.contact.Id, ProfileId = p.Id, Username = 'bs.portal.' + token + '@example.com.test',
            Email = 'portal.test@example.com', LastName = 'Portal', Alias = 'bsp' + token.left(5),
            CommunityNickname = 'bsp' + token, TimeZoneSidKey = 'Australia/Sydney', LocaleSidKey = 'en_AU',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        try {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert u;
            }
        } catch (DmlException e) {
            // If the org doesn't have "Allow using standard external profiles for self-registration,
            // user creation, and login" enabled, we can't create portal users in tests.
            // Skip the test by returning null - callers should check for null.
            if (e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION')
                && e.getMessage().contains('Allow using standard external profiles')) {
                return null;
            }
            throw e;
        }
        return u;
    }

    private static Set<Id> sharedUsers(Id propertyId) {
        Set<Id> ids = new Set<Id>();
        for (Property__Share s : [
            SELECT UserOrGroupId FROM Property__Share
            WHERE ParentId = :propertyId AND RowCause = :Schema.Property__Share.RowCause.Owner_Access__c
        ]) {
            ids.add(s.UserOrGroupId);
        }
        return ids;
    }

    @isTest
    static void ownershipCreatedAfterTheUserSharesTheProperty() {
        Profile p = portalProfile();
        if (p == null) {
            return;   // this org has no Customer Community Plus licence, so there is nothing to test
        }
        Fixture f = fixture();
        User u = createPortalUser(f, p);
        if (u == null) {
            return; // org doesn't allow portal user creation with standard external profiles
        }

        insert BillSplitTestData.ownershipRecord(f.s.property.Id, f.contact.Id, f.s.unitA.Id, 'Primary');

        System.assertEquals(new Set<Id>{ u.Id }, sharedUsers(f.s.property.Id));
    }

    @isTest
    static void userCreatedAfterTheOwnershipGetsAccessFromTheQueuedJob() {
        Profile p = portalProfile();
        if (p == null) {
            return;
        }
        Fixture f = fixture();
        insert BillSplitTestData.ownershipRecord(f.s.property.Id, f.contact.Id, f.s.unitA.Id, 'Primary');

        Test.startTest();
        User u = createPortalUser(f, p);
        if (u == null) {
            return; // org doesn't allow portal user creation with standard external profiles
        }
        Test.stopTest();

        System.assertEquals(new Set<Id>{ u.Id }, sharedUsers(f.s.property.Id));
    }

    @isTest
    static void endingTheOwnershipRemovesAccess() {
        Profile p = portalProfile();
        if (p == null) {
            return;
        }
        Fixture f = fixture();
        Ownership__c own = BillSplitTestData.ownershipRecord(f.s.property.Id, f.contact.Id, f.s.unitA.Id, 'Primary');
        insert own;
        Test.startTest();
        User u = createPortalUser(f, p);
        if (u == null) {
            return; // org doesn't allow portal user creation with standard external profiles
        }
        Test.stopTest();
        System.assertEquals(1, sharedUsers(f.s.property.Id).size());

        update new Ownership__c(Id = own.Id, End_Date__c = Date.today().addDays(-1));

        System.assertEquals(0, sharedUsers(f.s.property.Id).size());
    }

    @isTest
    static void theNightlyBatchRemovesStaleShares() {
        Profile p = portalProfile();
        if (p == null) {
            return;
        }
        Fixture f = fixture();
        User u = createPortalUser(f, p);
        if (u == null) {
            return; // org doesn't allow portal user creation with standard external profiles
        }
        // A share with no active ownership behind it, as left by an ownership that ended by date.
        insert new Property__Share(
            ParentId = f.s.property.Id, UserOrGroupId = u.Id, AccessLevel = 'Read',
            RowCause = Schema.Property__Share.RowCause.Owner_Access__c
        );
        System.assertEquals(1, sharedUsers(f.s.property.Id).size());

        Test.startTest();
        Database.executeBatch(new OwnershipSharingBatch(), 50);
        Test.stopTest();

        System.assertEquals(0, sharedUsers(f.s.property.Id).size());
    }

    @isTest
    static void syncDoesNothingForEmptyInput() {
        OwnershipSharingService.syncProperties(null);
        OwnershipSharingService.syncProperties(new Set<Id>());
        OwnershipSharingService.syncContacts(null);
        System.assertEquals(0, [SELECT COUNT() FROM Property__Share WHERE RowCause = :Schema.Property__Share.RowCause.Owner_Access__c]);
    }

    @isTest
    static void theBatchCanBeScheduled() {
        Test.startTest();
        String jobId = System.schedule('Bill Split sharing test', '0 0 3 * * ?', new OwnershipSharingBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}