/**
 * Tests for TriggerRecursionGuard class.
 */
@IsTest
private class TriggerRecursionGuardTest {

    @IsTest
    static void shouldAllowFirstExecution() {
        // Arrange
        String key = 'TestAction_BEFORE_INSERT';

        // Act & Assert
        System.assert(TriggerRecursionGuard.canExecute(key, 1));
    }

    @IsTest
    static void shouldBlockAfterMaxRecursion() {
        // Arrange
        String key = 'TestAction_BEFORE_INSERT';

        // Act
        System.assert(TriggerRecursionGuard.canExecute(key, 2), 'Should allow first');
        TriggerRecursionGuard.track(key);

        System.assert(TriggerRecursionGuard.canExecute(key, 2), 'Should allow second');
        TriggerRecursionGuard.track(key);

        // Assert
        System.assert(!TriggerRecursionGuard.canExecute(key, 2), 'Should block third');
    }

    @IsTest
    static void shouldAllowUnlimitedWhenMaxIsNull() {
        // Arrange
        String key = 'TestAction_BEFORE_INSERT';

        // Act & Assert
        for (Integer i = 0; i < 100; i++) {
            System.assert(TriggerRecursionGuard.canExecute(key, null));
            TriggerRecursionGuard.track(key);
        }
    }

    @IsTest
    static void shouldAllowUnlimitedWhenMaxIsZero() {
        // Arrange
        String key = 'TestAction_BEFORE_INSERT';

        // Act & Assert
        for (Integer i = 0; i < 100; i++) {
            System.assert(TriggerRecursionGuard.canExecute(key, 0));
            TriggerRecursionGuard.track(key);
        }
    }

    @IsTest
    static void shouldTrackDifferentKeysIndependently() {
        // Arrange
        String key1 = 'TestAction1_BEFORE_INSERT';
        String key2 = 'TestAction2_BEFORE_INSERT';

        // Act
        TriggerRecursionGuard.track(key1);
        TriggerRecursionGuard.track(key1);

        // Assert
        System.assert(!TriggerRecursionGuard.canExecute(key1, 2), 'Key1 should be blocked');
        System.assert(TriggerRecursionGuard.canExecute(key2, 2), 'Key2 should be allowed');
    }

    @IsTest
    static void shouldResetCountsForTesting() {
        // Arrange
        String key = 'TestAction_BEFORE_INSERT';
        TriggerRecursionGuard.track(key);
        TriggerRecursionGuard.track(key);
        
        // Verify it's blocked
        System.assert(!TriggerRecursionGuard.canExecute(key, 2), 'Should be blocked before reset');

        // Act
        TriggerRecursionGuard.reset();

        // Assert
        System.assert(TriggerRecursionGuard.canExecute(key, 2), 'Should be allowed after reset');
    }
}