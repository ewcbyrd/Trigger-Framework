/**
 * Utility class for test helper methods.
 */
@IsTest
public class TestUtility {

    private static Integer fakeIdCount = 1;

    /**
     * Generates a fake Salesforce ID for the given SObjectType.
     * Useful for creating test records without DML.
     */
    public static Id generateFakeId(Schema.SObjectType sObjectType) {
        String result = String.valueOf(fakeIdCount++);
        return (Id)(sObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - result.length()) + result);
    }
}