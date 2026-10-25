/**
 * Reads the Default record of Bill_Split_Setting__mdt and falls back to safe defaults.
 * Phase 4 adds the sender name and the email footer.
 */
public with sharing class BillSplitSettings {

    public static final Integer DEFAULT_MAX_UNITS = 2;
    public static final Integer DEFAULT_TOLERANCE_DAYS = 14;
    public static final String DEFAULT_FOOTER = 'Questions about this bill? Reply to this email.';

    @TestVisible private static Integer maxUnitsOverride;
    @TestVisible private static String orgWideNameOverride;
    @TestVisible private static Boolean orgWideNameOverrideSet = false;

    private static Bill_Split_Setting__mdt settings() {
        return Bill_Split_Setting__mdt.getInstance('Default');
    }

    public static Integer maxUnitsPerProperty() {
        if (maxUnitsOverride != null) {
            return maxUnitsOverride;
        }
        Bill_Split_Setting__mdt s = settings();
        if (s != null && s.Max_Units_Per_Property__c != null) {
            return Integer.valueOf(s.Max_Units_Per_Property__c);
        }
        return DEFAULT_MAX_UNITS;
    }

    public static Integer readingToleranceDays() {
        Bill_Split_Setting__mdt s = settings();
        if (s != null && s.Reading_Date_Tolerance_Days__c != null) {
            return Integer.valueOf(s.Reading_Date_Tolerance_Days__c);
        }
        return DEFAULT_TOLERANCE_DAYS;
    }

    /** Display name of the Org-Wide Email Address used as the sender. Blank means send from the running user. */
    public static String orgWideEmailName() {
        if (orgWideNameOverrideSet) {
            return orgWideNameOverride;
        }
        Bill_Split_Setting__mdt s = settings();
        return s == null || String.isBlank(s.Org_Wide_Email_Name__c) ? null : s.Org_Wide_Email_Name__c.trim();
    }

    public static String emailFooter() {
        Bill_Split_Setting__mdt s = settings();
        return s == null || String.isBlank(s.Email_Footer__c) ? DEFAULT_FOOTER : s.Email_Footer__c;
    }
}