// Creates an Experience Cloud (Customer Community Plus) user for an owner contact, for testing in a scratch org or sandbox.
// Edit the three values below, then run:  sf apex run -f scripts/apex/create-portal-user.apex -o billsplit
String contactEmail = 'naresh202501@gmail.com';      // the Contact to enable (must have an Account, the seed data does)
String testPassword = 'ChangeMe-12345!';            // used so you can log in without waiting for the welcome email
String profileName = 'Customer Community Plus User';

Contact c = [SELECT Id, FirstName, LastName, Email, AccountId FROM Contact WHERE Email = :contactEmail LIMIT 1];
Account acc = [SELECT Id, OwnerId, Owner.UserRoleId FROM Account WHERE Id = :c.AccountId];

// A portal account owner must have a role. Give the owner one if they have none.
if (acc.Owner.UserRoleId == null) {
    UserRole r = new UserRole(Name = 'Bill Split Admin', DeveloperName = 'Bill_Split_Admin');
    insert r;
    update new User(Id = acc.OwnerId, UserRoleId = r.Id);
    System.debug('Gave the account owner the role Bill Split Admin.');
}

Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
String stamp = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
User u = new User(
    ContactId = c.Id, ProfileId = p.Id, Username = contactEmail + '.owner' + stamp.left(4),
    Email = contactEmail, FirstName = c.FirstName, LastName = c.LastName, Alias = 'own' + stamp.left(5),
    CommunityNickname = 'owner' + stamp, TimeZoneSidKey = 'Australia/Sydney', LocaleSidKey = 'en_AU',
    EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
);
insert u;

List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('Bill_Split_Portal_Owner', 'Bill_Split_Portal_Access')]) {
    assignments.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
}
insert assignments;
System.setPassword(u.Id, testPassword);

System.debug('Created portal user ' + u.Username + ' with ' + assignments.size() + ' permission sets. Password: ' + testPassword);
System.debug('The share on the property is added by a queued job. Check: SELECT ParentId, UserOrGroupId, RowCause FROM Property__Share');
