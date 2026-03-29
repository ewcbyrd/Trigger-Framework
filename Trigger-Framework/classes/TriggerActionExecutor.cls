/**
 * Queries Trigger_Action__mdt, instantiates action classes via Type.forName(),
 * executes them in order, and enqueues async actions.
 */
public class TriggerActionExecutor {

    private static final String CONTEXT_SEPARATOR = '_';
    
    // Cache to store all metadata records, loaded once per transaction
    private static Map<String, List<Trigger_Action__mdt>> actionCache;
    private static Boolean cacheLoaded = false;

    /**
     * Main entry point called by TriggerDispatcher.
     */
    public static void execute(TriggerContext ctx, String sObjectName) {
        String contextName = resolveContextName(ctx.operationType);

        List<Trigger_Action__mdt> actions = getActions(sObjectName, contextName);

        List<IAsyncTriggerAction> asyncActions = new List<IAsyncTriggerAction>();

        for (Trigger_Action__mdt actionMdt : actions) {
            String actionKey = actionMdt.Class_Name__c + CONTEXT_SEPARATOR + contextName;

            // Recursion guard
            if (!TriggerRecursionGuard.canExecute(actionKey, (Integer) actionMdt.Max_Recursion__c)) {
                continue;
            }

            // Instantiate via reflection
            ITriggerAction action = createAction(actionMdt.Class_Name__c);

            // Track execution
            TriggerRecursionGuard.track(actionKey);

            // Execute synchronously (fail fast -- exceptions propagate)
            action.execute(ctx);

            // Collect async actions
            if (action instanceof IAsyncTriggerAction) {
                asyncActions.add((IAsyncTriggerAction) action);
            }
        }

        // Enqueue async work
        if (!asyncActions.isEmpty() && ctx.newMap != null) {
            System.enqueueJob(new TriggerAsyncQueueable(asyncActions, ctx.newMap.keySet()));
        }
    }

    /**
     * Loads all Custom Metadata records once per transaction and caches them.
     * Uses getAll() which doesn't count against SOQL governor limits.
     * Subsequent calls retrieve from cache without re-fetching metadata.
     */
    private static void loadCache() {
        if (cacheLoaded) {
            return;
        }
        
        actionCache = new Map<String, List<Trigger_Action__mdt>>();
        
        // Use getAll() to retrieve ALL trigger action metadata (no SOQL query)
        Map<String, Trigger_Action__mdt> allActionsMap = Trigger_Action__mdt.getAll();
        
        // Filter active records and group by SObject + Context
        for (Trigger_Action__mdt action : allActionsMap.values()) {
            // Skip inactive records
            if (action.Active__c != true) {
                continue;
            }
            
            String cacheKey = action.SObject__c + CONTEXT_SEPARATOR + action.Context__c;
            
            if (!actionCache.containsKey(cacheKey)) {
                actionCache.put(cacheKey, new List<Trigger_Action__mdt>());
            }
            
            actionCache.get(cacheKey).add(action);
        }
        
        cacheLoaded = true;
    }
    
    /**
     * Returns cached actions for the given SObject and context.
     * Loads cache if not already loaded (single SOQL query per transaction).
     */
    @TestVisible
    private static List<Trigger_Action__mdt> getActions(String sObjectName, String contextName) {
        // Ensure cache is loaded
        loadCache();
        
        String cacheKey = sObjectName + CONTEXT_SEPARATOR + contextName;
        
        // Return cached results (empty list if none found)
        if (actionCache.containsKey(cacheKey)) {
            return actionCache.get(cacheKey);
        }
        
        return new List<Trigger_Action__mdt>();
    }

    /**
     * Instantiates an ITriggerAction from a class name using Type.forName().
     * Throws a descriptive exception if the class cannot be found or doesn't implement ITriggerAction.
     */
    private static ITriggerAction createAction(String className) {
        Type actionType = Type.forName(className);
        if (actionType == null) {
            throw new TriggerFrameworkException(
                'Trigger action class not found: ' + className +
                '. Verify the class exists and is accessible from the running package.'
            );
        }
        Object instance = actionType.newInstance();
        if (!(instance instanceof ITriggerAction)) {
            throw new TriggerFrameworkException(
                'Class ' + className + ' does not implement ITriggerAction.'
            );
        }
        return (ITriggerAction) instance;
    }

    /**
     * Maps System.TriggerOperation enum to the Context__c picklist values
     * stored in Custom Metadata.
     */
    private static String resolveContextName(System.TriggerOperation op) {
        switch on op {
            when BEFORE_INSERT  { return 'BEFORE_INSERT'; }
            when BEFORE_UPDATE  { return 'BEFORE_UPDATE'; }
            when BEFORE_DELETE  { return 'BEFORE_DELETE'; }
            when AFTER_INSERT   { return 'AFTER_INSERT'; }
            when AFTER_UPDATE   { return 'AFTER_UPDATE'; }
            when AFTER_DELETE   { return 'AFTER_DELETE'; }
            when AFTER_UNDELETE { return 'AFTER_UNDELETE'; }
            when else {
                throw new TriggerFrameworkException('Unsupported trigger operation: ' + op);
            }
        }
    }
    
    /**
     * Clears the action cache. Useful for testing scenarios where you need to
     * verify cache behavior or reset state between test methods.
     */
    @TestVisible
    private static void clearCache() {
        actionCache = null;
        cacheLoaded = false;
    }
}