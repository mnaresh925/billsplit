public with sharing class UtilityAccountTriggerHandler {

    public static void beforeSave(List<Utility_Account__c> rows) {
        for (Utility_Account__c ua : rows) {
            if (ua.Property__c != null && String.isNotBlank(ua.Utility_Type__c) && String.isNotBlank(ua.Account_Number__c)) {
                ua.Account_Number__c = ua.Account_Number__c.trim();
                ua.Unique_Key__c = String.valueOf(ua.Property__c) + '|' + ua.Utility_Type__c + '|' + ua.Account_Number__c;
            }
        }
    }
}