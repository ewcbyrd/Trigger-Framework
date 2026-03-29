/**
 * Tests for TriggerDispatcher class.
 * All tests inject an empty cache so no deployed Custom Metadata records
 * interfere with execution.
 */
@IsTest
private class TriggerDispatcherTest {

    /**
     * Injects an empty action cache so dispatching never hits real metadata.
     */
    private static void injectEmptyCache() {
        TriggerActionExecutor.clearCache();
        TriggerActionExecutor.actionCache = new Map<String, List<Trigger_Action__mdt>>();
        TriggerActionExecutor.cacheLoaded = true;
    }

    /**
     * Builds a TriggerContext for Account with the given operation type.
     */
    private static TriggerContext buildAccountContext(System.TriggerOperation op) {
        Account testAccount = new Account(
            Id = TestUtility.generateFakeId(Account.SObjectType), Name = 'Test'
        );
        List<Account> records = new List<Account>{ testAccount };
        Map<Id, Account> recordMap = new Map<Id, Account>{ testAccount.Id => testAccount };

        Boolean isDelete = (op == System.TriggerOperation.BEFORE_DELETE ||
                            op == System.TriggerOperation.AFTER_DELETE);
        Boolean isInsertOrUndelete = (op == System.TriggerOperation.BEFORE_INSERT ||
                                      op == System.TriggerOperation.AFTER_INSERT ||
                                      op == System.TriggerOperation.AFTER_UNDELETE);

        return new TriggerContext(
            op,
            isDelete ? null : records,
            isDelete ? null : recordMap,
            isInsertOrUndelete ? null : records,
            isInsertOrUndelete ? null : recordMap
        );
    }

    @IsTest
    static void shouldDispatchWithTriggerContext() {
        // Arrange
        injectEmptyCache();
        TriggerContext ctx = buildAccountContext(System.TriggerOperation.BEFORE_INSERT);

        // Act
        Test.startTest();
        TriggerDispatcher.dispatch('Account', ctx);
        Test.stopTest();

        // Assert - Execution completed without error
        System.assert(true, 'Dispatch completed successfully');
    }

    @IsTest
    static void shouldDispatchAllTriggerOperations() {
        // Arrange — inject empty cache so no real metadata fires
        injectEmptyCache();

        // Act & Assert — every trigger operation dispatches without error
        Test.startTest();

        for (System.TriggerOperation op : System.TriggerOperation.values()) {
            TriggerContext ctx = buildAccountContext(op);
            TriggerDispatcher.dispatch('Account', ctx);
        }

        Test.stopTest();

        // All dispatches should complete without error
        System.assert(true, 'All trigger operations dispatched successfully');
    }

    @IsTest
    static void shouldDispatchFromActualTrigger() {
        // The public dispatch(String) method creates its own TriggerContext.
        // Outside a trigger context this should throw because Trigger.operationType is null.
        injectEmptyCache();

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            TriggerDispatcher.dispatch('Account');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown,
            'Expected exception when calling dispatch outside of a trigger context');
    }
}
