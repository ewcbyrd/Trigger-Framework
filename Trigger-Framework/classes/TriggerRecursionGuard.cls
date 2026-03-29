/**
 * Tracks execution counts per action class per trigger context
 * to enforce max recursion limits defined in Custom Metadata.
 */
public class TriggerRecursionGuard {

    private static Map<String, Integer> executionCounts = new Map<String, Integer>();

    /**
     * Returns true if the action is allowed to execute (hasn't exceeded max recursion).
     * @param actionKey Unique key: className + '_' + context
     * @param maxRecursion Max allowed executions. Null or 0 = unlimited.
     */
    public static Boolean canExecute(String actionKey, Integer maxRecursion) {
        if (maxRecursion == null || maxRecursion <= 0) {
            return true;
        }
        Integer count = executionCounts.get(actionKey);
        return count == null || count < maxRecursion;
    }

    /**
     * Increments the execution count for the given action key.
     */
    public static void track(String actionKey) {
        Integer count = executionCounts.get(actionKey);
        executionCounts.put(actionKey, count == null ? 1 : count + 1);
    }

    /**
     * Resets all counts. Intended for test setup only.
     */
    @TestVisible
    private static void reset() {
        executionCounts.clear();
    }
}