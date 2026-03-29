/**
 * Test action class for verifying execution order. Has Order__c = 5 (runs first).
 */
@isTest
public class TestOrderActionSecond implements ITriggerAction {

    public void execute(TriggerContext ctx) {
        TestOrderActionFirst.executionLog.add('Second');
    }
}
