/**
 * Test async action class for testing IAsyncTriggerAction interface.
 */
@isTest
public class TestAsyncAction implements ITriggerAction, IAsyncTriggerAction {
    
    public void execute(TriggerContext ctx) {
        // Test implementation - does nothing
    }
    
    public void executeAsync(Set<Id> recordIds) {
        // Test implementation - does nothing
    }
}
