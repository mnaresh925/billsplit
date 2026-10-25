// Demo data for Bill Split phase 1. Uses the worked example from the solution design.
// Run after assigning Bill_Split_Admin:  sf apex run -f scripts/apex/seed-data.apex -o <alias>
Id ownerRt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Property_Owner').getRecordTypeId();

Account acc = new Account(Name = 'Demo Household', RecordTypeId = ownerRt, Owner_Type__c = 'Joint');
insert acc;

Contact cA = new Contact(FirstName = 'Alex', LastName = 'Demo', AccountId = acc.Id, Email = 'alex.demo@example.com');
Contact cB = new Contact(FirstName = 'Sam', LastName = 'Demo', AccountId = acc.Id, Email = 'sam.demo@example.com',
                         Alternate_Billing_Email__c = 'sam.billing@example.com');
insert new List<Contact>{ cA, cB };

Property__c prop = new Property__c(
    Display_Name__c = '12 Banksia St (demo)', Street__c = '12 Banksia St', Suburb__c = 'Turner', State__c = 'ACT',
    Postcode__c = '2612', Location__Latitude__s = -35.2700, Location__Longitude__s = 149.1300,
    Address_Source__c = 'Map Pick', Council_Name__c = 'Demo Council', Status__c = 'Active');
insert prop;

Unit__c unitA = new Unit__c(Name = 'Unit A', Property__c = prop.Id, Same_As_Property_Address__c = false,
    Street__c = '12A Banksia St', Suburb__c = 'Turner', State__c = 'ACT', Postcode__c = '2612',
    Address_Source__c = 'Manual', Status__c = 'Occupied');
Unit__c unitB = new Unit__c(Name = 'Unit B', Property__c = prop.Id, Same_As_Property_Address__c = false,
    Street__c = '12B Banksia St', Suburb__c = 'Turner', State__c = 'ACT', Postcode__c = '2612',
    Address_Source__c = 'Manual', Status__c = 'Occupied');
insert new List<Unit__c>{ unitA, unitB };

insert new List<Ownership__c>{
    new Ownership__c(Property__c = prop.Id, Contact__c = cA.Id, Unit__c = unitA.Id, Role__c = 'Owner',
                     Bill_Email_Preference__c = 'Primary', Receives_Bills__c = true, Start_Date__c = Date.today().addYears(-2)),
    new Ownership__c(Property__c = prop.Id, Contact__c = cB.Id, Unit__c = unitB.Id, Role__c = 'Owner',
                     Bill_Email_Preference__c = 'Both', Receives_Bills__c = true, Start_Date__c = Date.today().addYears(-2))
};

Utility_Account__c ua = new Utility_Account__c(Property__c = prop.Id, Utility_Type__c = 'Water', Provider__c = 'Demo Council',
    Account_Number__c = 'DEMO-WATER-001', Billing_Frequency__c = 'Quarterly', Unit_Of_Measure__c = 'kL', Active__c = true);
insert ua;

Meter__c sub = new Meter__c(Name = 'SUB-0001', Utility_Account__c = ua.Id, Meter_Role__c = 'Sub', Unit__c = unitB.Id, Active__c = true);
insert sub;

Date periodEnd = Date.today().addDays(-1);
Date periodStart = periodEnd.addDays(-90);

insert new Meter_Reading__c(Meter__c = sub.Id, Reading_Date__c = periodStart.addDays(-1), Reading_Value__c = 1240,
    Reading_Type__c = 'Baseline', Source__c = 'Staff App');

Utility_Bill__c bill = new Utility_Bill__c(Utility_Account__c = ua.Id, Bill_Number__c = 'DEMO-0001',
    Issue_Date__c = Date.today(), Due_Date__c = Date.today().addDays(28), Period_Start__c = periodStart, Period_End__c = periodEnd,
    Total_Units_Consumed__c = 120, Total_Amount__c = 480.00, Supply_Charge__c = 60.00, Split_Method__c = 'Submeter Residual');
insert bill;

insert new Meter_Reading__c(Meter__c = sub.Id, Reading_Date__c = periodEnd, Reading_Value__c = 1278,
    Reading_Type__c = 'Bill Close', Utility_Bill__c = bill.Id, Source__c = 'Staff App');

System.debug('Seeded property ' + prop.Id + ' and bill ' + bill.Id + '. Expected split in phase 2: Unit B 163.00, Unit A 317.00.');
