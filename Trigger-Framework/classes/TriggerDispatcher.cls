/**
 * Entry point called from every trigger. Constructs TriggerContext
 * and delegates to TriggerActionExecutor.
 *
 * Usage in trigger:
 *   trigger AccountTrigger on Account (before insert, before update, ...) {
 *       TriggerDispatcher.dispatch('Account');
 *   }
 */
public class TriggerDispatcher {

    /**
     * Dispatches trigger processing for the specified SObject.
     * @param sObjectName The API name of the SObject (e.g., 'Account', 'My_Object__c').
     */
    public static void dispatch(String sObjectName) {
        TriggerContext ctx = new TriggerContext();
        TriggerActionExecutor.execute(ctx, sObjectName);
    }

    /**
     * Overload accepting an injected TriggerContext for testing.
     */
    @TestVisible
    private static void dispatch(String sObjectName, TriggerContext ctx) {
        TriggerActionExecutor.execute(ctx, sObjectName);
    }
}