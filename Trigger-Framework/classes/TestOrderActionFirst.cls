/**
 * Test action class for verifying execution order. Has Order__c = 50 (runs second).
 */
@isTest
public class TestOrderActionFirst implements ITriggerAction {

    public static List<String> executionLog = new List<String>();

    public void execute(TriggerContext ctx) {
        executionLog.add('First');
    }
}
