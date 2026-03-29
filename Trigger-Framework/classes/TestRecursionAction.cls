/**
 * Test action class with recursion limit for testing recursion guard.
 */
@isTest
public class TestRecursionAction implements ITriggerAction {
    
    public static Integer executionCount = 0;
    
    public void execute(TriggerContext ctx) {
        executionCount++;
    }
}
