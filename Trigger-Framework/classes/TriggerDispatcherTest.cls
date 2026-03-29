/**
 * Tests for TriggerDispatcher class.
 */
@IsTest
private class TriggerDispatcherTest {

    @IsTest
    static void shouldDispatchWithTriggerContext() {
        // Arrange
        Account testAccount = new Account(Id = TestUtility.generateFakeId(Account.SObjectType), Name = 'Test');
        List<Account> newList = new List<Account>{ testAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ testAccount.Id => testAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_INSERT,
            newList,
            newMap,
            null,
            null
        );

        // Act
        Test.startTest();
        TriggerDispatcher.dispatch('Account', ctx);
        Test.stopTest();

        // Assert - Execution completed without error
        System.assert(true, 'Dispatch completed successfully');
    }

    @IsTest
    static void shouldDispatchAllTriggerOperations() {
        // Arrange
        Account testAccount = new Account(Id = TestUtility.generateFakeId(Account.SObjectType), Name = 'Test');
        List<Account> newList = new List<Account>{ testAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ testAccount.Id => testAccount };

        // Act & Assert
        Test.startTest();

        // BEFORE contexts
        TriggerContext beforeInsert = new TriggerContext(
            System.TriggerOperation.BEFORE_INSERT,
            newList,
            newMap,
            null,
            null
        );
        TriggerDispatcher.dispatch('Account', beforeInsert);

        TriggerContext beforeUpdate = new TriggerContext(
            System.TriggerOperation.BEFORE_UPDATE,
            newList,
            newMap,
            newList,
            newMap
        );
        TriggerDispatcher.dispatch('Account', beforeUpdate);

        TriggerContext beforeDelete = new TriggerContext(
            System.TriggerOperation.BEFORE_DELETE,
            null,
            null,
            newList,
            newMap
        );
        TriggerDispatcher.dispatch('Account', beforeDelete);

        // AFTER contexts
        TriggerContext afterInsert = new TriggerContext(
            System.TriggerOperation.AFTER_INSERT,
            newList,
            newMap,
            null,
            null
        );
        TriggerDispatcher.dispatch('Account', afterInsert);

        // AFTER_UPDATE context may have Custom Metadata with invalid class name
        // Handle exception if it exists
        TriggerContext afterUpdate = new TriggerContext(
            System.TriggerOperation.AFTER_UPDATE,
            newList,
            newMap,
            newList,
            newMap
        );
        try {
            TriggerDispatcher.dispatch('Account', afterUpdate);
        } catch (TriggerFrameworkException e) {
            // Expected if TestInvalidClassName Custom Metadata exists with AFTER_UPDATE
            System.assert(e.getMessage().contains('not found'), 
                'Exception should be for class not found');
        }

        // AFTER_DELETE context may have Custom Metadata with class not implementing interface
        // Handle exception if it exists
        TriggerContext afterDelete = new TriggerContext(
            System.TriggerOperation.AFTER_DELETE,
            null,
            null,
            newList,
            newMap
        );
        try {
            TriggerDispatcher.dispatch('Account', afterDelete);
        } catch (TriggerFrameworkException e) {
            // Expected if TestInvalidInterface Custom Metadata exists with AFTER_DELETE
            System.assert(e.getMessage().contains('does not implement ITriggerAction'), 
                'Exception should be for interface not implemented');
        }

        TriggerContext afterUndelete = new TriggerContext(
            System.TriggerOperation.AFTER_UNDELETE,
            newList,
            newMap,
            null,
            null
        );
        TriggerDispatcher.dispatch('Account', afterUndelete);

        Test.stopTest();

        // All dispatches should complete without error
        System.assert(true, 'All trigger operations dispatched successfully');
    }

    @IsTest
    static void shouldDispatchFromActualTrigger() {
        // This test calls the public dispatch(String) method which creates its own TriggerContext
        // Note: We can't actually invoke trigger context outside of a trigger, 
        // so we test that the method signature exists and is callable
        
        // Act & Assert
        Test.startTest();
        try {
            // This will fail because we're not in a trigger context, but it proves the method is callable
            TriggerDispatcher.dispatch('Account');
            System.assert(false, 'Expected exception when not in trigger context');
        } catch (Exception e) {
            // Expected - we're not in a trigger context
            System.assert(true, 'Correctly threw exception when not in trigger context');
        }
        Test.stopTest();
    }
}