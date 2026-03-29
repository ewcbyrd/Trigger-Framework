/**
 * Test class that does NOT implement ITriggerAction - used for testing exception handling.
 */
@isTest
public class TestInvalidInterfaceClass {
    // This class intentionally does NOT implement ITriggerAction
    public void execute(TriggerContext ctx) {
        // This method exists but class doesn't implement the interface
    }
}
