/**
 * Tests for TriggerContext class.
 */
@IsTest
private class TriggerContextTest {

    @IsTest
    static void shouldConstructWithTestContext() {
        // Arrange
        Account testAccount = new Account(Id = TestUtility.generateFakeId(Account.SObjectType), Name = 'Test');
        List<Account> newList = new List<Account>{ testAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ testAccount.Id => testAccount };

        // Act
        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_INSERT,
            newList,
            newMap,
            null,
            null
        );

        // Assert
        System.assertEquals(System.TriggerOperation.BEFORE_INSERT, ctx.operationType);
        System.assertEquals(1, ctx.newList.size());
        System.assertEquals(1, ctx.size);
        System.assert(ctx.isBefore);
        System.assert(!ctx.isAfter);
        System.assert(ctx.isInsert);
        System.assert(!ctx.isUpdate);
    }

    @IsTest
    static void shouldDetectFieldChange() {
        // Arrange
        Id testId = TestUtility.generateFakeId(Account.SObjectType);
        Account oldAccount = new Account(Id = testId, Name = 'Old Name', BillingCountry = 'USA');
        Account newAccount = new Account(Id = testId, Name = 'New Name', BillingCountry = 'USA');

        List<Account> newList = new List<Account>{ newAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ newAccount.Id => newAccount };
        List<Account> oldList = new List<Account>{ oldAccount };
        Map<Id, Account> oldMap = new Map<Id, Account>{ oldAccount.Id => oldAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_UPDATE,
            newList,
            newMap,
            oldList,
            oldMap
        );

        // Act & Assert
        System.assert(ctx.hasChanged(newAccount, Account.Name));
        System.assert(!ctx.hasChanged(newAccount, Account.BillingCountry));
    }

    @IsTest
    static void shouldDetectMultipleFieldChanges() {
        // Arrange
        Id testId = TestUtility.generateFakeId(Account.SObjectType);
        Account oldAccount = new Account(Id = testId, Name = 'Old Name', BillingCountry = 'USA');
        Account newAccount = new Account(Id = testId, Name = 'New Name', BillingCountry = 'USA');

        List<Account> newList = new List<Account>{ newAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ newAccount.Id => newAccount };
        List<Account> oldList = new List<Account>{ oldAccount };
        Map<Id, Account> oldMap = new Map<Id, Account>{ oldAccount.Id => oldAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_UPDATE,
            newList,
            newMap,
            oldList,
            oldMap
        );

        List<SObjectField> fields = new List<SObjectField>{ Account.Name, Account.BillingCountry };

        // Act & Assert
        System.assert(ctx.hasChanged(newAccount, fields));
    }

    @IsTest
    static void shouldReturnOldValue() {
        // Arrange
        Id testId = TestUtility.generateFakeId(Account.SObjectType);
        Account oldAccount = new Account(Id = testId, Name = 'Old Name');
        Account newAccount = new Account(Id = testId, Name = 'New Name');

        List<Account> newList = new List<Account>{ newAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ newAccount.Id => newAccount };
        List<Account> oldList = new List<Account>{ oldAccount };
        Map<Id, Account> oldMap = new Map<Id, Account>{ oldAccount.Id => oldAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_UPDATE,
            newList,
            newMap,
            oldList,
            oldMap
        );

        // Act
        Object oldValue = ctx.getOldValue(newAccount, Account.Name);

        // Assert
        System.assertEquals('Old Name', oldValue);
    }

    @IsTest
    static void shouldReturnChangedRecordsForSingleField() {
        // Arrange
        Id testId1 = TestUtility.generateFakeId(Account.SObjectType);
        Id testId2 = TestUtility.generateFakeId(Account.SObjectType);
        Account oldAccount1 = new Account(Id = testId1, Name = 'Old Name 1');
        Account newAccount1 = new Account(Id = testId1, Name = 'New Name 1');
        Account oldAccount2 = new Account(Id = testId2, Name = 'Name 2');
        Account newAccount2 = new Account(Id = testId2, Name = 'Name 2');

        List<Account> newList = new List<Account>{ newAccount1, newAccount2 };
        Map<Id, Account> newMap = new Map<Id, Account>{ 
            newAccount1.Id => newAccount1, 
            newAccount2.Id => newAccount2 
        };
        List<Account> oldList = new List<Account>{ oldAccount1, oldAccount2 };
        Map<Id, Account> oldMap = new Map<Id, Account>{ 
            oldAccount1.Id => oldAccount1, 
            oldAccount2.Id => oldAccount2 
        };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_UPDATE,
            newList,
            newMap,
            oldList,
            oldMap
        );

        // Act
        List<SObject> changedRecords = ctx.getChangedRecords(Account.Name);

        // Assert
        System.assertEquals(1, changedRecords.size());
        System.assertEquals(testId1, changedRecords[0].Id);
    }

    @IsTest
    static void shouldReturnChangedRecordsForMultipleFields() {
        // Arrange
        Id testId1 = TestUtility.generateFakeId(Account.SObjectType);
        Id testId2 = TestUtility.generateFakeId(Account.SObjectType);
        Account oldAccount1 = new Account(Id = testId1, Name = 'Name 1', BillingCountry = 'USA');
        Account newAccount1 = new Account(Id = testId1, Name = 'Name 1', BillingCountry = 'Canada');
        Account oldAccount2 = new Account(Id = testId2, Name = 'Name 2', BillingCountry = 'USA');
        Account newAccount2 = new Account(Id = testId2, Name = 'Name 2', BillingCountry = 'USA');

        List<Account> newList = new List<Account>{ newAccount1, newAccount2 };
        Map<Id, Account> newMap = new Map<Id, Account>{ 
            newAccount1.Id => newAccount1, 
            newAccount2.Id => newAccount2 
        };
        List<Account> oldList = new List<Account>{ oldAccount1, oldAccount2 };
        Map<Id, Account> oldMap = new Map<Id, Account>{ 
            oldAccount1.Id => oldAccount1, 
            oldAccount2.Id => oldAccount2 
        };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_UPDATE,
            newList,
            newMap,
            oldList,
            oldMap
        );

        List<SObjectField> fields = new List<SObjectField>{ Account.Name, Account.BillingCountry };

        // Act
        List<SObject> changedRecords = ctx.getChangedRecords(fields);

        // Assert
        System.assertEquals(1, changedRecords.size());
        System.assertEquals(testId1, changedRecords[0].Id);
    }

    @IsTest
    static void shouldReturnTrueForInsertContext() {
        // Arrange
        Account testAccount = new Account(Id = TestUtility.generateFakeId(Account.SObjectType), Name = 'Test');
        List<Account> newList = new List<Account>{ testAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_INSERT,
            newList,
            null,
            null,
            null
        );

        // Act & Assert - hasChanged should return true for insert context
        System.assert(ctx.hasChanged(testAccount, Account.Name));
    }

    @IsTest
    static void shouldReturnRecordsWhereAllFieldsChanged() {
        // Arrange - Create two accounts, one with both fields changed, one with only one field changed
        Id testId1 = TestUtility.generateFakeId(Account.SObjectType);
        Id testId2 = TestUtility.generateFakeId(Account.SObjectType);

        Account oldAccount1 = new Account(Id = testId1, Name = 'Old Name 1', BillingCountry = 'US');
        Account newAccount1 = new Account(Id = testId1, Name = 'New Name 1', BillingCountry = 'CA');
        
        Account oldAccount2 = new Account(Id = testId2, Name = 'Old Name 2', BillingCountry = 'US');
        Account newAccount2 = new Account(Id = testId2, Name = 'New Name 2', BillingCountry = 'US'); // BillingCountry NOT changed

        List<Account> newList = new List<Account>{ newAccount1, newAccount2 };
        Map<Id, Account> newMap = new Map<Id, Account>{ testId1 => newAccount1, testId2 => newAccount2 };
        Map<Id, Account> oldMap = new Map<Id, Account>{ testId1 => oldAccount1, testId2 => oldAccount2 };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.AFTER_UPDATE,
            newList,
            newMap,
            new List<Account>{ oldAccount1, oldAccount2 },
            oldMap
        );

        List<SObjectField> fields = new List<SObjectField>{ Account.Name, Account.BillingCountry };

        // Act
        List<SObject> changedRecords = ctx.getChangedRecordsAll(fields);

        // Assert - Only account1 should be returned (both Name AND BillingCountry changed)
        System.assertEquals(1, changedRecords.size(), 'Should return only records where ALL fields changed');
        System.assertEquals(testId1, changedRecords[0].Id);
    }

    @IsTest
    static void shouldHandleDeleteContextWithNoNewList() {
        // Arrange - DELETE context has oldList/oldMap but no newList/newMap
        Id testId = TestUtility.generateFakeId(Account.SObjectType);
        Account oldAccount = new Account(Id = testId, Name = 'Deleted Account');
        List<Account> oldList = new List<Account>{ oldAccount };
        Map<Id, Account> oldMap = new Map<Id, Account>{ testId => oldAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.BEFORE_DELETE,
            null, // No newList in DELETE
            null, // No newMap in DELETE
            oldList,
            oldMap
        );

        // Act & Assert - getOldValue should return null when oldMap is null for the record
        Object oldValue = ctx.getOldValue(oldAccount, Account.Name);
        System.assertEquals('Deleted Account', oldValue, 'Should return old value in DELETE context');

        // Act & Assert - getChangedRecords should return empty list when newList is null
        List<SObject> changedSingle = ctx.getChangedRecords(Account.Name);
        System.assertEquals(0, changedSingle.size(), 'Should return empty list when newList is null');

        List<SObject> changedMultiple = ctx.getChangedRecords(new List<SObjectField>{ Account.Name });
        System.assertEquals(0, changedMultiple.size(), 'Should return empty list when newList is null');

        List<SObject> changedAll = ctx.getChangedRecordsAll(new List<SObjectField>{ Account.Name, Account.BillingCountry });
        System.assertEquals(0, changedAll.size(), 'Should return empty list when newList is null');
    }

    @IsTest
    static void shouldHandleInsertContextWithNoOldMap() {
        // Arrange - INSERT context has no oldList/oldMap
        Id testId = TestUtility.generateFakeId(Account.SObjectType);
        Account newAccount = new Account(Id = testId, Name = 'New Account');
        List<Account> newList = new List<Account>{ newAccount };
        Map<Id, Account> newMap = new Map<Id, Account>{ testId => newAccount };

        TriggerContext ctx = new TriggerContext(
            System.TriggerOperation.AFTER_INSERT,
            newList,
            newMap,
            null, // No oldList in INSERT
            null  // No oldMap in INSERT
        );

        // Act & Assert - getOldValue should return null when oldMap is null
        Object oldValue = ctx.getOldValue(newAccount, Account.Name);
        System.assertEquals(null, oldValue, 'Should return null when oldMap is null (INSERT context)');
    }
}