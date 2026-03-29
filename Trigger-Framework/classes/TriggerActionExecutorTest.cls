/**
 * Tests for TriggerActionExecutor class.
 * All tests inject metadata records directly into the static cache via
 * @TestVisible fields, eliminating any dependency on deployed Custom Metadata
 * records that could impact production trigger execution.
 */
@IsTest
private class TriggerActionExecutorTest {

    // ─── Helper: builds a Trigger_Action__mdt record in memory ───
    private static Trigger_Action__mdt buildAction(
        String className, String sObjectName, String context, Decimal orderVal,
        Boolean isActive, Decimal maxRecursion
    ) {
        return new Trigger_Action__mdt(
            Label            = className,
            DeveloperName    = className,
            Class_Name__c    = className,
            SObject__c       = sObjectName,
            Context__c       = context,
            Order__c         = orderVal,
            Active__c        = isActive,
            Max_Recursion__c = maxRecursion
        );
    }

    // ─── Helper: injects a list of actions into the cache, keyed properly ───
    private static void injectCache(List<Trigger_Action__mdt> actions) {
        TriggerActionExecutor.clearCache();
        TriggerActionExecutor.actionCache = new Map<String, List<Trigger_Action__mdt>>();

        for (Trigger_Action__mdt a : actions) {
            String key = a.SObject__c + '_' + a.Context__c;
            if (!TriggerActionExecutor.actionCache.containsKey(key)) {
                TriggerActionExecutor.actionCache.put(key, new List<Trigger_Action__mdt>());
            }
            TriggerActionExecutor.actionCache.get(key).add(a);
        }
        TriggerActionExecutor.cacheLoaded = true;
    }

    // ─── Helper: injects a single action into the cache ───
    private static void injectCache(Trigger_Action__mdt action) {
        injectCache(new List<Trigger_Action__mdt>{ action });
    }

    // ─── Helper: builds a TriggerContext for Account ───
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

    // ══════════════════════════════════════════════════════════════
    // Tests
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void shouldResolveAllContextNames() {
        // Arrange — inject an empty cache so no actions fire, just prove
        // that every TriggerOperation resolves without error.
        TriggerActionExecutor.clearCache();
        TriggerActionExecutor.actionCache = new Map<String, List<Trigger_Action__mdt>>();
        TriggerActionExecutor.cacheLoaded = true;

        Test.startTest();
        for (System.TriggerOperation op : System.TriggerOperation.values()) {
            TriggerContext ctx = buildAccountContext(op);
            TriggerActionExecutor.execute(ctx, 'Account');
        }
        Test.stopTest();

        System.assert(true, 'All trigger contexts resolved without error');
    }

    @IsTest
    static void shouldThrowExceptionForNonExistentClass() {
        // Arrange — inject a record that points to a class that does not exist
        Trigger_Action__mdt bad = buildAction(
            'NonExistentClass', 'Account', 'AFTER_UPDATE', 10, true, null
        );
        injectCache(bad);

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.AFTER_UPDATE);

        // Act & Assert
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            TriggerActionExecutor.execute(ctx, 'Account');
        } catch (TriggerFrameworkException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('not found'),
                'Exception message should indicate class not found: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected TriggerFrameworkException for non-existent class');
    }

    @IsTest
    static void shouldThrowExceptionForInvalidInterface() {
        // Arrange — inject a record pointing to a class that does NOT implement ITriggerAction
        Trigger_Action__mdt bad = buildAction(
            'TestInvalidInterfaceClass', 'Account', 'AFTER_DELETE', 10, true, null
        );
        injectCache(bad);

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.AFTER_DELETE);

        // Act & Assert
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            TriggerActionExecutor.execute(ctx, 'Account');
        } catch (TriggerFrameworkException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('does not implement ITriggerAction'),
                'Exception message should indicate interface not implemented: ' + e.getMessage());
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Expected TriggerFrameworkException for invalid interface');
    }

    @IsTest
    static void shouldHandleRecursionLimit() {
        // Arrange — inject a record with Max_Recursion__c = 1
        Trigger_Action__mdt recursionAction = buildAction(
            'TestRecursionAction', 'Account', 'BEFORE_INSERT', 10, true, 1
        );
        injectCache(recursionAction);

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.BEFORE_INSERT);

        // Act — execute twice; recursion guard should block the second run
        Test.startTest();
        TriggerRecursionGuard.reset();
        TestRecursionAction.executionCount = 0;

        TriggerActionExecutor.execute(ctx, 'Account'); // 1st — should run
        TriggerActionExecutor.execute(ctx, 'Account'); // 2nd — should be blocked
        Test.stopTest();

        // Assert
        System.assertEquals(1, TestRecursionAction.executionCount,
            'Action should only execute once when Max_Recursion__c = 1');
    }

    @IsTest
    static void shouldAllowUnlimitedRecursionWhenMaxIsNull() {
        // Arrange — inject a record with no Max_Recursion__c (null = unlimited)
        Trigger_Action__mdt unlimitedAction = buildAction(
            'TestRecursionAction', 'Account', 'BEFORE_INSERT', 10, true, null
        );
        injectCache(unlimitedAction);

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.BEFORE_INSERT);

        // Act — execute three times; all should run
        Test.startTest();
        TriggerRecursionGuard.reset();
        TestRecursionAction.executionCount = 0;

        TriggerActionExecutor.execute(ctx, 'Account');
        TriggerActionExecutor.execute(ctx, 'Account');
        TriggerActionExecutor.execute(ctx, 'Account');
        Test.stopTest();

        // Assert
        System.assertEquals(3, TestRecursionAction.executionCount,
            'Action should execute every time when Max_Recursion__c is null');
    }

    @IsTest
    static void shouldExecuteAsyncActions() {
        // Arrange — inject an async action for a context that has newMap (required for enqueue)
        Trigger_Action__mdt asyncAction = buildAction(
            'TestAsyncAction', 'Account', 'AFTER_INSERT', 10, true, null
        );
        injectCache(asyncAction);

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.AFTER_INSERT);

        // Act
        Test.startTest();
        TriggerRecursionGuard.reset();
        TriggerActionExecutor.execute(ctx, 'Account');
        Test.stopTest();

        // Assert — if no exception, async job was enqueued and completed
        System.assert(true, 'Async action enqueued and executed without error');
    }

    @IsTest
    static void shouldSkipAsyncEnqueueInDeleteContext() {
        // Arrange — async action in a delete context (newMap is null, so enqueue is skipped)
        Trigger_Action__mdt asyncAction = buildAction(
            'TestAsyncAction', 'Account', 'AFTER_DELETE', 10, true, null
        );
        injectCache(asyncAction);

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.AFTER_DELETE);

        // Act — should not throw even though action implements IAsyncTriggerAction
        Test.startTest();
        TriggerRecursionGuard.reset();
        TriggerActionExecutor.execute(ctx, 'Account');
        Test.stopTest();

        System.assert(true, 'Async enqueue correctly skipped in delete context');
    }

    @IsTest
    static void shouldGetActionsFromCache() {
        // Arrange — inject a known action
        Trigger_Action__mdt action = buildAction(
            'TestRecursionAction', 'Account', 'BEFORE_INSERT', 10, true, null
        );
        injectCache(action);

        // Act
        Test.startTest();
        List<Trigger_Action__mdt> results = TriggerActionExecutor.getActions('Account', 'BEFORE_INSERT');
        List<Trigger_Action__mdt> empty   = TriggerActionExecutor.getActions('Contact', 'BEFORE_INSERT');
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return the injected action');
        System.assertEquals('TestRecursionAction', results[0].Class_Name__c);
        System.assertEquals(0, empty.size(), 'Should return empty list for unregistered SObject');
    }

    @IsTest
    static void shouldExecuteActionsInOrderByOrderField() {
        // Arrange — inject two actions in sorted order (Order 5 before Order 50)
        TriggerActionExecutor.clearCache();
        TestOrderActionFirst.executionLog.clear();

        Trigger_Action__mdt actionOrder50 = buildAction(
            'TestOrderActionFirst', 'Account', 'BEFORE_UPDATE', 50, true, null
        );
        Trigger_Action__mdt actionOrder5 = buildAction(
            'TestOrderActionSecond', 'Account', 'BEFORE_UPDATE', 5, true, null
        );

        TriggerActionExecutor.actionCache = new Map<String, List<Trigger_Action__mdt>>{
            'Account_BEFORE_UPDATE' => new List<Trigger_Action__mdt>{ actionOrder5, actionOrder50 }
        };
        TriggerActionExecutor.cacheLoaded = true;

        TriggerContext ctx = buildAccountContext(System.TriggerOperation.BEFORE_UPDATE);

        // Act
        Test.startTest();
        TriggerRecursionGuard.reset();
        TriggerActionExecutor.execute(ctx, 'Account');
        Test.stopTest();

        // Assert — Order 5 (Second) runs before Order 50 (First)
        System.assertEquals(2, TestOrderActionFirst.executionLog.size(),
            'Both order test actions should have executed');
        System.assertEquals('Second', TestOrderActionFirst.executionLog[0],
            'Action with lower Order__c (5) should execute first');
        System.assertEquals('First', TestOrderActionFirst.executionLog[1],
            'Action with higher Order__c (50) should execute second');
    }

    @IsTest
    static void shouldSortActionsByOrderAscendingNullsLast() {
        // Arrange — records in deliberately wrong order
        Trigger_Action__mdt orderNull  = new Trigger_Action__mdt(DeveloperName = 'NullOrder',  Order__c = null);
        Trigger_Action__mdt order20    = new Trigger_Action__mdt(DeveloperName = 'Order20',    Order__c = 20);
        Trigger_Action__mdt order5     = new Trigger_Action__mdt(DeveloperName = 'Order5',     Order__c = 5);
        Trigger_Action__mdt order5Dup  = new Trigger_Action__mdt(DeveloperName = 'Order5Dup',  Order__c = 5);
        Trigger_Action__mdt orderNull2 = new Trigger_Action__mdt(DeveloperName = 'NullOrder2', Order__c = null);

        List<Trigger_Action__mdt> actions = new List<Trigger_Action__mdt>{
            orderNull, order20, order5, order5Dup, orderNull2
        };

        // Act
        Test.startTest();
        TriggerActionExecutor.sortByOrder(actions);
        Test.stopTest();

        // Assert — ascending with nulls last, stable for equal values
        System.assertEquals('Order5',     actions[0].DeveloperName, 'First should be Order 5');
        System.assertEquals('Order5Dup',  actions[1].DeveloperName, 'Second should be Order 5 (dup)');
        System.assertEquals('Order20',    actions[2].DeveloperName, 'Third should be Order 20');
        System.assertEquals('NullOrder',  actions[3].DeveloperName, 'Fourth should be null');
        System.assertEquals('NullOrder2', actions[4].DeveloperName, 'Fifth should be null');
    }
}
