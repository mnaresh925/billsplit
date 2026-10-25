/**
 * Saves everything the property setup wizard collects in one transaction: property, two units, owners
 * (existing or new contacts), the utility account, the optional sub-meter and its baseline reading.
 *
 * The wizard sends one JSON string shaped like Payload. DML uses "as user" so object and field permissions
 * of the staff member apply. Trigger and validation rule errors come back as readable messages and the
 * whole transaction is rolled back.
 */
public with sharing class PropertySetupController {

    public class Address {
        public String street;
        public String suburb;
        public String state;
        public String postcode;
        public Decimal latitude;
        public Decimal longitude;
        public String source;
    }

    public class PropertyIn {
        public String displayName;
        public String councilName;
        public String ratesAssessmentNo;
        public Address address;
    }

    public class UnitIn {
        public String label;
        public Boolean sameAsProperty;
        public String status;
        public Address address;
    }

    public class NewContact {
        public String firstName;
        public String lastName;
        public String email;
        public String alternateEmail;
    }

    public class OwnerIn {
        public Id contactId;
        public NewContact newContact;
        /** 0 or 1 = that unit, null = the whole property. */
        public Integer unitIndex;
        public String role;
        public String preference;
        public Boolean receivesBills;
        public Date startDate;
    }

    public class UtilityIn {
        public String utilityType;
        public String provider;
        public String accountNumber;
        public String billingFrequency;
        public String unitOfMeasure;
        public Boolean hasSubMeter;
        public String meterName;
        public Integer meterUnitIndex;
        public Decimal baselineValue;
        public Date baselineDate;
    }

    public class Payload {
        public PropertyIn property;
        public List<UnitIn> units;
        public List<OwnerIn> owners;
        public UtilityIn utility;
    }

    public class SaveResult {
        @AuraEnabled public Id propertyId;
        @AuraEnabled public Integer unitCount;
        @AuraEnabled public Integer ownerCount;
        @AuraEnabled public Integer newContactCount;
        @AuraEnabled public Id utilityAccountId;
        @AuraEnabled public Id meterId;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    private static final String SOURCE_MAP = 'Map Pick';
    private static final String SOURCE_MANUAL = 'Manual';

    @AuraEnabled
    public static SaveResult save(String payloadJson) {
        Payload p;
        try {
            p = (Payload) JSON.deserialize(payloadJson, Payload.class);
        } catch (Exception e) {
            throw aura('The setup details could not be read. Reload the page and try again.');
        }
        Savepoint sp = Database.setSavepoint();
        try {
            validate(p);
            return doSave(p);
        } catch (Exception e) {
            Database.rollback(sp);
            throw toAura(e);
        }
    }

    // ------------------------------------------------------------------ validation

    @TestVisible
    private static void validate(Payload p) {
        if (p == null || p.property == null) {
            throw new BillSplitException('Property details are required.');
        }
        if (String.isBlank(p.property.displayName)) {
            throw new BillSplitException('Enter a property name.');
        }
        requireAddress(p.property.address, 'property');
        if (p.units == null || p.units.size() != 2) {
            throw new BillSplitException('A dual occupancy property needs exactly 2 units.');
        }
        Set<String> labels = new Set<String>();
        for (UnitIn u : p.units) {
            if (String.isBlank(u.label)) {
                throw new BillSplitException('Every unit needs a label.');
            }
            if (!labels.add(u.label.trim().toLowerCase())) {
                throw new BillSplitException('Unit labels must be different.');
            }
            if (u.sameAsProperty != true) {
                requireAddress(u.address, 'unit "' + u.label + '"');
            }
        }
        if (p.owners == null || p.owners.isEmpty()) {
            throw new BillSplitException('Add at least one owner.');
        }
        for (OwnerIn o : p.owners) {
            if (o.contactId == null) {
                if (o.newContact == null || String.isBlank(o.newContact.lastName) || String.isBlank(o.newContact.email)) {
                    throw new BillSplitException('Each new owner needs a last name and an email address.');
                }
            }
            if (o.unitIndex != null && (o.unitIndex < 0 || o.unitIndex > 1)) {
                throw new BillSplitException('An owner is linked to a unit that does not exist.');
            }
            if (String.isBlank(o.role) || String.isBlank(o.preference)) {
                throw new BillSplitException('Choose a role and an email preference for every owner.');
            }
        }
        if (p.utility == null || String.isBlank(p.utility.accountNumber)) {
            throw new BillSplitException('Enter the utility account number.');
        }
        if (p.utility.hasSubMeter == true) {
            if (String.isBlank(p.utility.meterName) || p.utility.meterUnitIndex == null
                || p.utility.baselineValue == null || p.utility.baselineDate == null) {
                throw new BillSplitException('The sub-meter needs a meter number, the unit it serves, and a baseline reading with its date.');
            }
            if (p.utility.meterUnitIndex < 0 || p.utility.meterUnitIndex > 1) {
                throw new BillSplitException('The sub-meter is linked to a unit that does not exist.');
            }
        }
    }

    private static void requireAddress(Address a, String what) {
        if (a == null || String.isBlank(a.street) || String.isBlank(a.suburb)
            || String.isBlank(a.state) || String.isBlank(a.postcode)) {
            throw new BillSplitException('Enter a street, suburb, state and postcode for the ' + what + '.');
        }
    }

    // ------------------------------------------------------------------ saving

    private static SaveResult doSave(Payload p) {
        SaveResult result = new SaveResult();

        Property__c prop = new Property__c(
            Display_Name__c = p.property.displayName.trim(),
            Council_Name__c = p.property.councilName,
            Rates_Assessment_No__c = p.property.ratesAssessmentNo,
            Status__c = 'Active'
        );
        applyAddress(prop, p.property.address);
        insert as user prop;
        result.propertyId = prop.Id;

        List<Unit__c> units = new List<Unit__c>();
        for (UnitIn u : p.units) {
            Unit__c unit = new Unit__c(
                Name = u.label.trim(), Property__c = prop.Id,
                Status__c = String.isBlank(u.status) ? 'Occupied' : u.status,
                Same_As_Property_Address__c = u.sameAsProperty == true
            );
            if (u.sameAsProperty == true) {
                // The Unit trigger copies the property address. Source is still required on the record.
                unit.Address_Source__c = prop.Address_Source__c;
            } else {
                applyAddress(unit, u.address);
            }
            units.add(unit);
        }
        insert as user units;
        result.unitCount = units.size();

        List<Id> contactIds = resolveContacts(p.owners, result);

        List<Ownership__c> ownerships = new List<Ownership__c>();
        for (Integer i = 0; i < p.owners.size(); i++) {
            OwnerIn o = p.owners[i];
            ownerships.add(new Ownership__c(
                Property__c = prop.Id,
                Unit__c = o.unitIndex == null ? null : units[o.unitIndex].Id,
                Contact__c = contactIds[i],
                Role__c = o.role,
                Bill_Email_Preference__c = o.preference,
                Receives_Bills__c = o.receivesBills == true,
                Start_Date__c = o.startDate == null ? Date.today() : o.startDate
            ));
        }
        insert as user ownerships;
        result.ownerCount = ownerships.size();

        Utility_Account__c ua = new Utility_Account__c(
            Property__c = prop.Id,
            Utility_Type__c = String.isBlank(p.utility.utilityType) ? 'Water' : p.utility.utilityType,
            Provider__c = p.utility.provider,
            Account_Number__c = p.utility.accountNumber.trim(),
            Billing_Frequency__c = String.isBlank(p.utility.billingFrequency) ? 'Quarterly' : p.utility.billingFrequency,
            Unit_Of_Measure__c = String.isBlank(p.utility.unitOfMeasure) ? 'kL' : p.utility.unitOfMeasure,
            Active__c = true
        );
        insert as user ua;
        result.utilityAccountId = ua.Id;

        if (p.utility.hasSubMeter == true) {
            Meter__c meter = new Meter__c(
                Name = p.utility.meterName.trim(), Utility_Account__c = ua.Id,
                Unit__c = units[p.utility.meterUnitIndex].Id, Meter_Role__c = 'Sub', Active__c = true
            );
            insert as user meter;
            result.meterId = meter.Id;

            insert as user new Meter_Reading__c(
                Meter__c = meter.Id, Reading_Type__c = 'Baseline', Reading_Date__c = p.utility.baselineDate,
                Reading_Value__c = p.utility.baselineValue, Source__c = 'Staff App'
            );
        }
        return result;
    }

    /**
     * New contacts each get their own Property Owner account ("<Last name> household"), so two owners who are
     * different households never share an account. Existing contacts keep their account. An existing contact
     * with no account is allowed but reported, because such a contact cannot be given a portal login.
     */
    private static List<Id> resolveContacts(List<OwnerIn> owners, SaveResult result) {
        List<Id> ids = new List<Id>();
        List<Contact> toInsert = new List<Contact>();
        List<Integer> insertPositions = new List<Integer>();
        Set<Id> existingIds = new Set<Id>();
        for (Integer i = 0; i < owners.size(); i++) {
            OwnerIn o = owners[i];
            ids.add(o.contactId);
            if (o.contactId == null) {
                toInsert.add(new Contact(
                    FirstName = o.newContact.firstName, LastName = o.newContact.lastName.trim(),
                    Email = o.newContact.email.trim(), Alternate_Billing_Email__c = o.newContact.alternateEmail
                ));
                insertPositions.add(i);
            } else {
                existingIds.add(o.contactId);
            }
        }
        result.newContactCount = toInsert.size();

        if (!existingIds.isEmpty()) {
            for (Contact c : [SELECT Name FROM Contact WHERE Id IN :existingIds AND AccountId = null]) {
                result.warnings.add(c.Name + ' has no Account, so they cannot be given an owner portal login until one is added.');
            }
        }
        if (toInsert.isEmpty()) {
            return ids;
        }
        List<Account> households = new List<Account>();
        for (Contact c : toInsert) {
            households.add(household(c.LastName));
        }
        insert as user households;
        for (Integer k = 0; k < toInsert.size(); k++) {
            toInsert[k].AccountId = households[k].Id;
        }
        insert as user toInsert;
        for (Integer k = 0; k < insertPositions.size(); k++) {
            ids[insertPositions[k]] = toInsert[k].Id;
        }
        return ids;
    }

    private static Account household(String lastName) {
        Account acc = new Account(Name = lastName + ' household');
        Schema.RecordTypeInfo rt = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Property_Owner');
        if (rt != null) {
            acc.RecordTypeId = rt.getRecordTypeId();
        }
        return acc;
    }

    private static void applyAddress(SObject record, Address a) {
        record.put('Street__c', a.street.trim());
        record.put('Suburb__c', a.suburb.trim());
        record.put('State__c', a.state);
        record.put('Postcode__c', a.postcode.trim());
        Boolean hasPoint = a.latitude != null && a.longitude != null;
        if (hasPoint && a.source != SOURCE_MANUAL) {
            record.put('Location__Latitude__s', a.latitude);
            record.put('Location__Longitude__s', a.longitude);
            record.put('Address_Source__c', SOURCE_MAP);
        } else {
            record.put('Address_Source__c', SOURCE_MANUAL);
        }
    }

    // ------------------------------------------------------------------ errors

    private static AuraHandledException aura(String msg) {
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        return ae;
    }

    private static AuraHandledException toAura(Exception e) {
        String msg = e.getMessage();
        if (e instanceof DmlException) {
            msg = ((DmlException) e).getDmlMessage(0);
        }
        return aura(msg);
    }
}