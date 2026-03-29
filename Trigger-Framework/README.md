# Trigger Framework

A multi-package Salesforce trigger framework designed for extensibility using Custom Metadata and polymorphism. Supports both synchronous and asynchronous (Queueable) execution patterns.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
- [Class Reference](#class-reference)
  - [Interfaces](#interfaces-1)
  - [Core Classes](#core-classes)
  - [Test Utilities](#test-utilities)
  - [Custom Metadata Type](#custom-metadata-type)
- [TriggerContext Utilities](#triggercontext-utilities)
- [Real-World Examples](#real-world-examples)
  - [Example 1: Opportunity Stage Change Tracking](#example-1-opportunity-stage-change-tracking)
  - [Example 2: Contact Address Synchronization](#example-2-contact-address-synchronization)
  - [Example 3: Lead Assignment with Multiple Criteria](#example-3-lead-assignment-with-multiple-criteria)
  - [Example 4: Case Escalation with Field Tracking](#example-4-case-escalation-with-field-tracking)
  - [Example 5: Async Data Enrichment](#example-5-async-data-enrichment)
  - [Example 6: Before Delete Validation](#example-6-before-delete-validation)
  - [Example 7: After Undelete Recovery](#example-7-after-undelete-recovery)
- [Examples Quick Reference](#examples-quick-reference)
- [Execution Order](#execution-order)
- [Recursion Prevention](#recursion-prevention)
- [Testing](#testing)
- [Best Practices](#best-practices)
- [Error Handling & Debugging](#error-handling--debugging)
- [Deployment Guide](#deployment-guide)
- [Troubleshooting](#troubleshooting)
- [Multi-Package Architecture](#multi-package-architecture)
- [Available Trigger Contexts](#available-trigger-contexts)

## Overview

This framework enables a clean, maintainable trigger architecture where:
- One trigger per object (zero logic in the trigger itself)
- Each piece of business logic is a discrete class implementing `ITriggerAction`
- Logic is registered via `Trigger_Action__mdt` Custom Metadata
- Extension packages can add their own actions without modifying the base package
- Built-in recursion prevention and field change detection utilities
- Testable with mock trigger context injection

### Execution Flow

```
Trigger fires (e.g., AccountTrigger)
  |
  v
TriggerDispatcher.dispatch('Account')
  |-- Creates TriggerContext (wraps Trigger.* variables)
  |
  v
TriggerActionExecutor.execute(ctx, 'Account')
  |-- resolveContextName(AFTER_UPDATE) --> 'AFTER_UPDATE'
  |-- loadCache() [once per transaction, uses getAll() -- 0 SOQL]
  |-- getActions('Account', 'AFTER_UPDATE') --> cached metadata records
  |
  |-- For each active, ordered Trigger_Action__mdt record:
  |     |-- canExecute(actionKey, maxRecursion)  [recursion check]
  |     |-- createAction(className)              [Type.forName() reflection]
  |     |-- track(actionKey)                     [increment count]
  |     |-- action.execute(ctx)                  [synchronous, fail-fast]
  |     |-- if instanceof IAsyncTriggerAction --> collect for later
  |
  v
If async actions exist AND ctx.newMap != null:
  System.enqueueJob(TriggerAsyncQueueable)
    |-- For each async action:
          action.executeAsync(recordIds)  [separate governor limits]
```

## Quick Start

### 1. Create a Trigger

```apex
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    TriggerDispatcher.dispatch('Account');
}
```

### 2. Create an Action Class

**Before Insert Example:**
```apex
public class AccountValidateBillingCountry implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        for (SObject record : ctx.newList) {
            Account acc = (Account) record;
            if (String.isBlank(acc.BillingCountry)) {
                acc.addError('Billing Country is required.');
            }
        }
    }
}
```

**After Insert Example:**
```apex
public class AccountCreateDefaultOpportunity implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        List<Opportunity> opps = new List<Opportunity>();
        
        for (SObject record : ctx.newList) {
            Account acc = (Account) record;
            opps.add(new Opportunity(
                Name = acc.Name + ' - Default Opportunity',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        
        if (!opps.isEmpty()) {
            insert opps;
        }
    }
}
```

**After Update Example (with field change detection):**
```apex
public class AccountStatusChangeNotification implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        // Only process records where Status field changed
        List<SObject> changedAccounts = ctx.getChangedRecords(Account.Status__c);
        
        for (SObject record : changedAccounts) {
            Account newAccount = (Account) record;
            Account oldAccount = (Account) ctx.oldMap.get(newAccount.Id);
            
            String oldStatus = (String) ctx.getOldValue(newAccount, Account.Status__c);
            String newStatus = newAccount.Status__c;
            
            // Send notification about status change
            System.debug('Account ' + newAccount.Name + ' status changed from ' 
                + oldStatus + ' to ' + newStatus);
            // Add your notification logic here
        }
    }
}
```

**Asynchronous Example:**
```apex
public class AccountSyncToExternalSystem implements IAsyncTriggerAction {
    public void execute(TriggerContext ctx) {
        // Optional sync logic - runs immediately in the transaction
    }

    public void executeAsync(Set<Id> recordIds) {
        // This runs asynchronously via Queueable
        List<Account> accounts = [SELECT Id, Name, BillingCountry FROM Account WHERE Id IN :recordIds];
        // Call external service
        ExternalSystemService.syncAccounts(accounts);
    }
}
```

### 3. Register the Actions

Create `Trigger_Action__mdt` records for each action:

**Before Insert Validation:**
| Field | Value |
|-------|-------|
| Label | `Account_BeforeInsert_ValidateBillingCountry` |
| SObject__c | `Account` |
| Context__c | `BEFORE_INSERT` |
| Class_Name__c | `AccountValidateBillingCountry` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

**After Insert Record Creation:**
| Field | Value |
|-------|-------|
| Label | `Account_AfterInsert_CreateDefaultOpportunity` |
| SObject__c | `Account` |
| Context__c | `AFTER_INSERT` |
| Class_Name__c | `AccountCreateDefaultOpportunity` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

**After Update Notification:**
| Field | Value |
|-------|-------|
| Label | `Account_AfterUpdate_StatusChangeNotification` |
| SObject__c | `Account` |
| Context__c | `AFTER_UPDATE` |
| Class_Name__c | `AccountStatusChangeNotification` |
| Order__c | `20` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

**After Update Async Sync:**
| Field | Value |
|-------|-------|
| Label | `Account_AfterUpdate_SyncToExternalSystem` |
| SObject__c | `Account` |
| Context__c | `AFTER_UPDATE` |
| Class_Name__c | `AccountSyncToExternalSystem` |
| Order__c | `30` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

## Core Components

### Interfaces

- **ITriggerAction** - Contract for synchronous actions
- **IAsyncTriggerAction** - Contract for async actions (extends ITriggerAction)

### Classes

- **TriggerDispatcher** - Entry point called from triggers
- **TriggerActionExecutor** - Orchestrates action execution
- **TriggerContext** - Wraps Trigger.* variables with utility methods
- **TriggerRecursionGuard** - Prevents infinite recursion
- **TriggerAsyncQueueable** - Executes async actions via Queueable

### Custom Metadata

- **Trigger_Action__mdt** - Configuration records that map SObjects + Contexts to action classes

---

## Class Reference

### Interfaces

#### ITriggerAction

**Purpose:** Base interface that all synchronous trigger actions must implement.

**Location:** `classes/ITriggerAction.cls`

**Methods:**

```apex
void execute(TriggerContext ctx);
```

**Parameters:**
- `ctx` - TriggerContext wrapper containing Trigger.* variables and utility methods

**Usage:**
```apex
public class MyAction implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        // Your logic here
    }
}
```

**When to Use:**
- Validation logic
- Field updates on trigger records
- Creating/updating related records
- Any logic that must complete synchronously

---

#### IAsyncTriggerAction

**Purpose:** Interface for actions that need asynchronous execution. Extends `ITriggerAction`.

**Location:** `classes/IAsyncTriggerAction.cls`

**Methods:**

```apex
void execute(TriggerContext ctx);           // Inherited from ITriggerAction
void executeAsync(Set<Id> recordIds);       // New async method
```

**Parameters:**
- `ctx` - TriggerContext for synchronous validation/processing
- `recordIds` - Set of record IDs to process asynchronously

**Usage:**
```apex
public class MyAsyncAction implements IAsyncTriggerAction {
    public void execute(TriggerContext ctx) {
        // Optional: Sync validation before async execution
    }
    
    public void executeAsync(Set<Id> recordIds) {
        // Runs asynchronously via Queueable
        // Has separate governor limits
    }
}
```

**When to Use:**
- External API callouts (HTTP)
- Heavy computational processing
- Large data volume operations
- Operations that can fail without blocking user

**Execution Flow:**
1. `execute()` runs synchronously in the trigger transaction
2. Framework collects all record IDs
3. After all sync actions complete, framework enqueues `executeAsync()`
4. Queueable job executes with fresh governor limits

> **Note:** Async actions are only enqueued when `ctx.newMap` is not null. This means `executeAsync()` will **not** run in `BEFORE_DELETE` or `AFTER_DELETE` contexts, since there are no "new" records. The synchronous `execute()` method still runs in delete contexts. If you need async processing for deleted records, handle it manually within `execute()`.

---

### Core Classes

#### TriggerDispatcher

**Purpose:** Entry point that should be called from all triggers. Routes execution to TriggerActionExecutor.

**Location:** `classes/TriggerDispatcher.cls`

**Methods:**

```apex
public static void dispatch(String sObjectName)
```

**Parameters:**
- `sObjectName` - API name of the SObject (e.g., 'Account', 'CustomObject__c')

**Test-Only Overload (`@TestVisible private`):**

```apex
@TestVisible
private static void dispatch(String sObjectName, TriggerContext ctx)
```

- `ctx` - Mock TriggerContext for testing (only accessible from `@IsTest` classes)

**Usage in Trigger:**
```apex
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    TriggerDispatcher.dispatch('Account');
}
```

**Usage in Tests (with mock context):**
```apex
TriggerContext mockCtx = new TriggerContext(
    System.TriggerOperation.BEFORE_INSERT,
    new List<Account>{ new Account(Name='Test') },
    null, null, null
);
TriggerDispatcher.dispatch('Account', mockCtx);
```

> **Note:** Both the test constructor on `TriggerContext` and the test overload on `TriggerDispatcher` are `private` with `@TestVisible`. They are only accessible from `@IsTest` classes.

**Behavior:**
- Automatically detects trigger context (before/after, insert/update/delete/undelete)
- Creates TriggerContext wrapper from Trigger.* variables
- Delegates to TriggerActionExecutor
- Only executes if actually inside a trigger (unless mock context provided)

---

#### TriggerActionExecutor

**Purpose:** Orchestrates the loading and execution of trigger actions from Custom Metadata.

**Location:** `classes/TriggerActionExecutor.cls`

**Methods:**

```apex
public static void execute(TriggerContext ctx, String sObjectName)
```

**Parameters:**
- `ctx` - TriggerContext containing trigger data
- `sObjectName` - API name of the SObject

**Internal Process:**
1. Loads ALL `Trigger_Action__mdt` records via `getAll()` on first execution (no SOQL)
2. Filters active records and caches them grouped by SObject + Context
3. Retrieves matching actions for current SObject + Context from cache
4. Orders actions by `Order__c` ascending (nulls last)
5. Instantiates each action class via `Type.forName()`
6. Checks recursion guard for each action
7. Executes synchronous actions in order
8. Collects async actions and enqueues them via `TriggerAsyncQueueable`

**Metadata Loading (Global Cache):**
```apex
// Uses Custom Metadata getAll() method - NO SOQL query!
Map<String, Trigger_Action__mdt> allActionsMap = Trigger_Action__mdt.getAll();
```
- **No SOQL Consumption:** `getAll()` does NOT count against the 100 SOQL query limit
- **Platform Cached:** Metadata is cached by Salesforce platform for optimal performance
- **Executed once per transaction:** First trigger execution loads all metadata, filters by `Active__c`
- **Results grouped:** By `SObject__c + '_' + Context__c` in static Map
- **Subsequent lookups:** Retrieved from memory with zero overhead

**Performance & Caching:**
- **Global Cache Strategy:** ALL metadata records loaded via `getAll()` on first trigger execution
- **Zero SOQL Impact:** Custom Metadata `getAll()` does not consume SOQL queries
- **Query Frequency:** **0 SOQL queries per transaction** for metadata loading
- **Cache Lifetime:** Lasts for entire transaction, automatically cleared between transactions
- **Governor Limit Optimization:** Frees up all 100 SOQL queries for your action class logic
- **Memory Efficient:** Filters only active metadata records, shared across all trigger executions
- **Scalable:** Works identically whether you have 1 or 100 different SObject triggers configured

**Example Scenarios:**
```apex
// Scenario 1: Single Account update
update account;  
// Metadata Queries: 0 (getAll() doesn't count)
// Your action classes have full 100 SOQL queries available

// Scenario 2: Account + Contact updates in same transaction
update account;
update contact;
// Metadata Queries: 0 (getAll() doesn't count)

// Scenario 3: Complex workflow with 5 different objects
update account;   // Loads cache via getAll() (0 queries)
update contact;   // From cache (0 queries)
update opportunity; // From cache (0 queries)
update case;      // From cache (0 queries)
update lead;      // From cache (0 queries)
// Total Metadata Queries: 0 (regardless of SObject count)

// Scenario 4: Recursive trigger scenario
update account;  // Loads cache via getAll(), action modifies related records
// Recursive triggers fire for Account, Contact, etc.
// Total Metadata Queries: 0 (cache prevents re-fetching on any recursive execution)
```

**Error Handling:**
- Throws `TriggerFrameworkException` if class name is invalid
- Throws exception if class doesn't implement ITriggerAction
- Propagates exceptions from action classes (fail-fast)

**Recursion Prevention:**
- Uses `TriggerRecursionGuard` before each action execution
- Skips actions that exceed their `Max_Recursion__c` limit

**Not Typically Called Directly:** Use `TriggerDispatcher.dispatch()` instead.

---

#### TriggerContext

**Purpose:** Wrapper around Trigger.* variables with field change detection utilities.

**Location:** `classes/TriggerContext.cls`

**Properties:**

```apex
public System.TriggerOperation operationType  // Trigger.operationType
public List<SObject> newList                  // Trigger.new
public Map<Id, SObject> newMap                // Trigger.newMap
public List<SObject> oldList                  // Trigger.old
public Map<Id, SObject> oldMap                // Trigger.oldMap
public Boolean isBefore                       // Trigger.isBefore
public Boolean isAfter                        // Trigger.isAfter
public Boolean isInsert                       // Trigger.isInsert
public Boolean isUpdate                       // Trigger.isUpdate
public Boolean isDelete                       // Trigger.isDelete
public Boolean isUndelete                     // Trigger.isUndelete
public Integer size                           // Trigger.size
```

All properties have `public` getters and `private` setters.

**Constructors:**

**Production (public, no-arg):**
```apex
public TriggerContext()
```
Reads all values directly from `Trigger.*` system context variables.

**Test (`@TestVisible private`):**
```apex
@TestVisible
private TriggerContext(
    System.TriggerOperation operationType,
    List<SObject> newList,
    Map<Id, SObject> newMap,
    List<SObject> oldList,
    Map<Id, SObject> oldMap
)
```
Derives boolean flags (`isBefore`, `isAfter`, etc.) from the `operationType` enum name. Only accessible from `@IsTest` classes.

**Methods:**

##### hasChanged (single field)

```apex
public Boolean hasChanged(SObject record, SObjectField field)
```

Checks if a specific field changed on a record.

**Parameters:**
- `record` - The new record from ctx.newList
- `field` - SObjectField token (e.g., Account.Name)

**Returns:** `true` if field value changed, `false` otherwise

**Example:**
```apex
if (ctx.hasChanged(account, Account.BillingCity)) {
    // City changed
}
```

---

##### hasChanged (multiple fields - OR logic)

```apex
public Boolean hasChanged(SObject record, List<SObjectField> fields)
```

Checks if ANY of the specified fields changed (OR logic).

**Parameters:**
- `record` - The new record from ctx.newList
- `fields` - List of SObjectField tokens

**Returns:** `true` if at least one field changed, `false` otherwise

**Example:**
```apex
List<SObjectField> fields = new List<SObjectField>{ 
    Account.Name, 
    Account.Phone 
};
if (ctx.hasChanged(account, fields)) {
    // Name OR Phone changed
}
```

---

##### getOldValue

```apex
public Object getOldValue(SObject record, SObjectField field)
```

Gets the previous value of a field from oldMap.

**Parameters:**
- `record` - The new record from ctx.newList
- `field` - SObjectField token

**Returns:** Previous field value, or null if not available

**Example:**
```apex
String oldStatus = (String) ctx.getOldValue(opp, Opportunity.StageName);
String newStatus = opp.StageName;
System.debug('Changed from ' + oldStatus + ' to ' + newStatus);
```

---

##### getChangedRecords (single field)

```apex
public List<SObject> getChangedRecords(SObjectField field)
```

Returns all records where the specified field changed.

**Parameters:**
- `field` - SObjectField token

**Returns:** List of records with field changes

**Example:**
```apex
// Only process records where Stage changed
for (SObject record : ctx.getChangedRecords(Opportunity.StageName)) {
    Opportunity opp = (Opportunity) record;
    // Process changed opportunities
}
```

---

##### getChangedRecords (multiple fields - OR logic)

```apex
public List<SObject> getChangedRecords(List<SObjectField> fields)
```

Returns records where ANY of the specified fields changed (OR logic).

**Parameters:**
- `fields` - List of SObjectField tokens

**Returns:** List of records where at least one field changed

**Example:**
```apex
List<SObjectField> addressFields = new List<SObjectField>{
    Account.BillingStreet,
    Account.BillingCity,
    Account.BillingState
};

// Returns accounts where ANY address field changed
List<SObject> changed = ctx.getChangedRecords(addressFields);
```

---

##### getChangedRecordsAll (multiple fields - AND logic)

```apex
public List<SObject> getChangedRecordsAll(List<SObjectField> fields)
```

Returns records where ALL of the specified fields changed (AND logic).

**Parameters:**
- `fields` - List of SObjectField tokens

**Returns:** List of records where every specified field changed

**Example:**
```apex
List<SObjectField> fields = new List<SObjectField>{
    Contact.FirstName,
    Contact.LastName,
    Contact.Email
};

// Returns contacts where ALL three fields changed
List<SObject> allChanged = ctx.getChangedRecordsAll(fields);
```

**Comparison:**
```apex
// OR logic - At least one field changed
ctx.getChangedRecords(fields);

// AND logic - All fields must have changed
ctx.getChangedRecordsAll(fields);
```

---

#### TriggerRecursionGuard

**Purpose:** Prevents infinite recursion by tracking action execution counts using a composite key per action per context.

**Location:** `classes/TriggerRecursionGuard.cls`

**Methods:**

```apex
public static Boolean canExecute(String actionKey, Integer maxRecursion)
public static void track(String actionKey)
```

**Parameters:**
- `actionKey` - Composite key: `className + '_' + contextName` (e.g., `'AccountValidation_AFTER_UPDATE'`)
- `maxRecursion` - Maximum allowed executions. `null` or `0` = unlimited.

**Returns (`canExecute`):** `true` if action is allowed to execute, `false` if limit reached

**Usage Pattern (internal to framework):**
```apex
String actionKey = 'AccountValidation' + '_' + 'AFTER_UPDATE';

if (TriggerRecursionGuard.canExecute(actionKey, 1)) {
    TriggerRecursionGuard.track(actionKey);
    // Execute action
}
```

**Static State:**
- Uses `static Map<String, Integer>` to track counts (flat map with composite keys)
- Persists for entire transaction
- Automatically reset between transactions

**Test Support:**
```apex
// @TestVisible private method for resetting state between test methods
TriggerRecursionGuard.reset();
```

**Not Typically Called Directly:** Framework handles recursion checking automatically.

---

#### TriggerAsyncQueueable

**Purpose:** Queueable job that executes async actions from `IAsyncTriggerAction`.

**Location:** `classes/TriggerAsyncQueueable.cls`

**Constructor:**

```apex
public TriggerAsyncQueueable(
    List<IAsyncTriggerAction> actions,
    Set<Id> recordIds
)
```

**Parameters:**
- `actions` - List of async actions to execute
- `recordIds` - Set of record IDs to process

**Methods:**

```apex
public void execute(QueueableContext context)
```

**Behavior:**
1. Executes each async action's `executeAsync(recordIds)` method sequentially
2. Exceptions propagate naturally (fail-fast) -- if one async action throws, subsequent actions do not execute
3. Runs with fresh governor limits (separate from trigger transaction)

**Error Handling:**
- No try/catch -- exceptions propagate up from the Queueable execution
- A failing async action will cause the Queueable job to fail (visible in Setup > Apex Jobs)
- If you need per-action error isolation, add try/catch inside your `executeAsync()` implementation

**Governor Limits:**
- Queueable: 50 chained jobs per transaction
- Async apex limits apply (not trigger limits)
- SOQL: 100 queries
- DML: 150 statements
- Heap: 12 MB (async context)

**Not Typically Instantiated Directly:** Framework enqueues automatically when `IAsyncTriggerAction` actions are registered.

---

#### TriggerFrameworkException

**Purpose:** Custom exception class for framework-specific errors.

**Location:** `classes/TriggerFrameworkException.cls`

**Usage:**
```apex
throw new TriggerFrameworkException('Action class not found: ' + className);
```

**Extends:** System.Exception

**Common Scenarios:**
- Class name not found in org
- Class doesn't implement ITriggerAction
- Invalid configuration in Custom Metadata

---

### Test Utilities

#### TestUtility

**Purpose:** Helper class for generating fake record IDs in unit tests.

**Location:** `classes/TestUtility.cls`

**Methods:**

```apex
public static Id generateFakeId(Schema.SObjectType sObjectType)
```

**Parameters:**
- `sObjectType` - SObject type (e.g., Account.SObjectType)

**Returns:** Valid 18-character Salesforce ID (auto-increments internally to guarantee uniqueness)

**Usage:**
```apex
@IsTest
static void testAction() {
    // Generate fake IDs for testing
    Id fakeAccountId = TestUtility.generateFakeId(Account.SObjectType);
    Id fakeContactId = TestUtility.generateFakeId(Contact.SObjectType);
    
    Account oldAccount = new Account(
        Id = fakeAccountId,
        Name = 'Old Name'
    );
    
    Account newAccount = new Account(
        Id = fakeAccountId,
        Name = 'New Name'
    );
    
    // Create mock context
    TriggerContext ctx = new TriggerContext(
        System.TriggerOperation.AFTER_UPDATE,
        new List<Account>{ newAccount },
        new Map<Id, SObject>{ fakeAccountId => newAccount },
        new List<Account>{ oldAccount },
        new Map<Id, SObject>{ fakeAccountId => oldAccount }
    );
    
    // Test your action
    MyAction action = new MyAction();
    action.execute(ctx);
}
```

**Why Needed:**
- SObject records without IDs don't support field change detection
- Can't insert test records in unit tests for trigger actions
- Provides realistic IDs for proper testing

---

### Custom Metadata Type

#### Trigger_Action__mdt

**Purpose:** Configuration records that register trigger actions with the framework.

**Location:** `objects/Trigger_Action__mdt/`

**Fields:**

| Field API Name | Type | Length/Precision | Required | Default |
|----------------|------|------------------|----------|---------|
| `Label` | Text(80) | 80 | Yes | - |
| `SObject__c` | Text(255) | 255 | Yes | - |
| `Context__c` | Text(255) | 255 | Yes | - |
| `Class_Name__c` | Text(255) | 255 | Yes | - |
| `Order__c` | Number(5,1) | precision=5, scale=1 | No | null |
| `Active__c` | Checkbox | - | No | `true` |
| `Max_Recursion__c` | Number(2,0) | precision=2, scale=0 | No | null |
| `Description__c` | Long Text Area(32768) | 32768 | No | - |

**Valid Context Values:**
- `BEFORE_INSERT`
- `BEFORE_UPDATE`
- `BEFORE_DELETE`
- `AFTER_INSERT`
- `AFTER_UPDATE`
- `AFTER_DELETE`
- `AFTER_UNDELETE`

**Best Practices:**
- Use descriptive labels: `{Object}_{Context}_{Description}`
- Order in increments of 10: 10, 20, 30 (allows insertion)
- Set `Max_Recursion__c = 1` for most actions (no default value -- blank means unlimited)
- Use `Description__c` to document business logic for maintainability
- Set `Active__c = false` to temporarily disable without deleting

**Example Record:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Account_AfterUpdate_StatusNotification</label>
    <protected>false</protected>
    <values>
        <field>Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Class_Name__c</field>
        <value xsi:type="xsd:string">AccountStatusChangeNotification</value>
    </values>
    <values>
        <field>Context__c</field>
        <value xsi:type="xsd:string">AFTER_UPDATE</value>
    </values>
    <values>
        <field>Description__c</field>
        <value xsi:type="xsd:string">Sends notification when account status changes</value>
    </values>
    <values>
        <field>Max_Recursion__c</field>
        <value xsi:type="xsd:double">1.0</value>
    </values>
    <values>
        <field>Order__c</field>
        <value xsi:type="xsd:double">20.0</value>
    </values>
    <values>
        <field>SObject__c</field>
        <value xsi:type="xsd:string">Account</value>
    </values>
</CustomMetadata>
```

**Layout:**
- Standard layout available: `Trigger_Action__mdt-Trigger Action Layout`
- Includes all custom fields plus `NamespacePrefix` (read-only)
- Located in: `layouts/Trigger_Action__mdt-Trigger Action Layout.layout-meta.xml`

---

## TriggerContext Utilities

### Field Change Detection

```apex
public void execute(TriggerContext ctx) {
    // Check if a specific field changed
    if (ctx.hasChanged(account, Account.Name)) {
        // Name changed
    }

    // Check if any of multiple fields changed (OR logic)
    List<SObjectField> fields = new List<SObjectField>{ Account.Name, Account.Phone };
    if (ctx.hasChanged(account, fields)) {
        // At least one field changed
    }

    // Get old value
    String oldName = (String) ctx.getOldValue(account, Account.Name);

    // Get only records where a specific field changed
    List<SObject> nameChangedRecords = ctx.getChangedRecords(Account.Name);

    // Get records where ANY of the specified fields changed (OR logic)
    List<SObject> anyChangedRecords = ctx.getChangedRecords(
        new List<SObjectField>{ Account.Name, Account.Phone }
    );

    // Get records where ALL of the specified fields changed (AND logic)
    List<SObject> allChangedRecords = ctx.getChangedRecordsAll(
        new List<SObjectField>{ Account.Name, Account.Phone }
    );
}
```

### Complex Field Change Logic

For complex AND/OR combinations, use the built-in methods with custom filtering:

```apex
public void execute(TriggerContext ctx) {
    // Example: (Name changed OR Phone changed) AND Email changed
    List<SObject> results = new List<SObject>();
    
    for (SObject record : ctx.newList) {
        Boolean nameOrPhoneChanged = ctx.hasChanged(record, Account.Name) 
            || ctx.hasChanged(record, Account.Phone);
        Boolean emailChanged = ctx.hasChanged(record, Account.Email);
        
        if (nameOrPhoneChanged && emailChanged) {
            results.add(record);
        }
    }
    
    // Example: Get intersection of two result sets
    // Records where Name changed AND (Phone OR Email changed)
    List<SObject> nameChanged = ctx.getChangedRecords(Account.Name);
    Set<Id> phoneOrEmailChanged = new Set<Id>();
    
    for (SObject record : ctx.getChangedRecords(
        new List<SObjectField>{ Account.Phone, Account.Email }
    )) {
        phoneOrEmailChanged.add(record.Id);
    }
    
    List<SObject> intersection = new List<SObject>();
    for (SObject record : nameChanged) {
        if (phoneOrEmailChanged.contains(record.Id)) {
            intersection.add(record);
        }
    }
}
```

## Execution Order

Actions execute in ascending order based on `Order__c` (nulls last). Use increments of 10 (10, 20, 30...) to leave room for insertion:

```
Order 10:  ValidateRequiredFields
Order 20:  EnrichData
Order 25:  NewActionInsertedBetween (added later without reordering)
Order 30:  SyncToExternalSystem (async)
```

## Recursion Prevention

Each action can specify `Max_Recursion__c`:
- `null` or `0` - No limit (unlimited executions)
- `1` (recommended) - Execute once per transaction
- `n` - Execute up to n times

> **Important:** `Max_Recursion__c` has no default value at the field level. If left blank, the framework treats it as unlimited. Set it to `1` explicitly on each metadata record unless you specifically need multiple executions.

## Testing

### Unit Testing Actions

```apex
@IsTest
static void testAction() {
    // Arrange
    Account acc = new Account(Name = 'Test', BillingCountry = null);
    TriggerContext ctx = new TriggerContext(
        System.TriggerOperation.BEFORE_INSERT,
        new List<Account>{ acc },
        null,
        null,
        null
    );

    AccountValidateBillingCountry action = new AccountValidateBillingCountry();

    // Act
    action.execute(ctx);

    // Assert - verify behavior
}
```

### Integration Testing

```apex
@IsTest
static void testIntegration() {
    // Arrange - Create Custom Metadata records (if using mocking framework)
    Account acc = new Account(Name = 'Test');

    // Act
    Test.startTest();
    insert acc; // Trigger fires, framework executes registered actions
    Test.stopTest();

    // Assert
    // Verify the actions executed correctly
}
```

### Testing Async Actions

```apex
@IsTest
static void testAsyncAction() {
    // Arrange
    Account acc = new Account(Name = 'Test', Website = 'www.example.com');
    insert acc;

    // Act
    Test.startTest();
    update acc; // Trigger fires, async action is enqueued
    Test.stopTest(); // Forces async execution to complete

    // Assert
    Account updated = [SELECT Id, Industry, NumberOfEmployees FROM Account WHERE Id = :acc.Id];
    System.assertNotEquals(null, updated.Industry, 'Industry should be enriched');
}
```

---

## Best Practices

### Action Class Design

**DO:**
- ✅ Keep actions focused on a single responsibility
- ✅ Make actions bulkified (process all records in ctx.newList)
- ✅ Use meaningful, descriptive class names (e.g., `AccountValidateBillingCountry`)
- ✅ Add comments explaining the business logic
- ✅ Handle null values and edge cases
- ✅ Use field change detection to minimize processing

**DON'T:**
- ❌ Put multiple unrelated pieces of logic in one action
- ❌ Query inside loops
- ❌ Perform DML inside loops
- ❌ Make callouts in synchronous actions (use IAsyncTriggerAction)
- ❌ Rely on execution order between different actions
- ❌ Catch and suppress exceptions without logging

### Bulkification

All actions must handle bulk operations (up to 200 records):

```apex
// ❌ BAD - Not bulkified
public void execute(TriggerContext ctx) {
    for (SObject record : ctx.newList) {
        Account acc = (Account) record;
        // Query inside loop - governor limit violation!
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acc.Id];
        // DML inside loop - governor limit violation!
        insert new Opportunity(Name = acc.Name, AccountId = acc.Id);
    }
}

// ✅ GOOD - Bulkified
public void execute(TriggerContext ctx) {
    Set<Id> accountIds = new Set<Id>();
    List<Opportunity> oppsToInsert = new List<Opportunity>();
    
    // Collect IDs
    for (SObject record : ctx.newList) {
        accountIds.add(record.Id);
    }
    
    // Single query outside loop
    Map<Id, List<Contact>> contactsByAccount = new Map<Id, List<Contact>>();
    for (Contact con : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
        if (!contactsByAccount.containsKey(con.AccountId)) {
            contactsByAccount.put(con.AccountId, new List<Contact>());
        }
        contactsByAccount.get(con.AccountId).add(con);
    }
    
    // Collect records to insert
    for (SObject record : ctx.newList) {
        Account acc = (Account) record;
        oppsToInsert.add(new Opportunity(Name = acc.Name, AccountId = acc.Id));
    }
    
    // Single DML outside loop
    if (!oppsToInsert.isEmpty()) {
        insert oppsToInsert;
    }
}
```

### Sync vs Async Decision Guide

Use **synchronous** actions when:
- ✅ Validation logic that should block the transaction
- ✅ Data enrichment that must complete before user sees success
- ✅ Field updates on the same record
- ✅ Fast operations (< 1 second)
- ✅ Need to add errors to records

Use **asynchronous** actions when:
- ✅ External API callouts
- ✅ Processing large data volumes
- ✅ Operations that can fail without blocking user
- ✅ Creating many related records
- ✅ Long-running calculations

### Naming Conventions

Follow this pattern for consistency:

**Class Names:**
```
{ObjectName}{Context}{Description}
Examples:
- AccountValidateBillingCountry
- OpportunityCreateRenewal
- LeadAssignToQueue
```

**Custom Metadata Labels:**
```
{ObjectName}_{Context}_{Description}
Examples:
- Account_BeforeInsert_ValidateBillingCountry
- Opportunity_AfterUpdate_CreateRenewal
- Lead_AfterInsert_AssignToQueue
```

**Order Numbers:**
Use increments of 10 to allow insertion:
- 10, 20, 30, 40, 50... (not 1, 2, 3, 4, 5...)

---

## Error Handling & Debugging

### Adding Validation Errors

In `BEFORE` contexts, you can prevent DML by adding errors:

```apex
public void execute(TriggerContext ctx) {
    for (SObject record : ctx.newList) {
        Account acc = (Account) record;
        if (String.isBlank(acc.BillingCountry)) {
            // Blocks the entire transaction
            acc.addError('Billing Country is required.');
        }
    }
}
```

### Exception Handling

```apex
public void execute(TriggerContext ctx) {
    try {
        // Your logic here
    } catch (Exception e) {
        // Log the error
        System.debug(LoggingLevel.ERROR, 'Error in AccountAction: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        
        // Re-throw to fail transaction, or handle gracefully
        throw new TriggerFrameworkException('Failed to process accounts: ' + e.getMessage(), e);
    }
}
```

### Debugging Tips

**Check if action is registered:**
```apex
List<Trigger_Action__mdt> actions = [
    SELECT Label, SObject__c, Context__c, Class_Name__c, Active__c, Order__c
    FROM Trigger_Action__mdt
    WHERE SObject__c = 'Account'
    AND Context__c = 'AFTER_UPDATE'
    ORDER BY Order__c NULLS LAST
];
System.debug('Registered actions: ' + actions);
```

**Add debug statements in your action:**
```apex
public void execute(TriggerContext ctx) {
    System.debug('Action executing with ' + ctx.size + ' records');
    System.debug('Context: ' + ctx.operationType);
    
    List<SObject> changed = ctx.getChangedRecords(Account.Name);
    System.debug('Records with changed Name: ' + changed.size());
    
    // Your logic
}
```

**Check recursion guard:**
```apex
// In Developer Console or Debug Logs, look for:
// "Recursion limit reached for action: AccountValidateBillingCountry"
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Action doesn't fire | Not registered in Custom Metadata | Create Trigger_Action__mdt record |
| Action doesn't fire | Active__c = false | Set Active__c to true |
| Action doesn't fire | Wrong Context__c value | Use exact values: BEFORE_INSERT, AFTER_UPDATE, etc. |
| Action fires too many times | Max_Recursion__c too high or null | Set Max_Recursion__c = 1 |
| "Class does not exist" error | Typo in Class_Name__c | Verify class name matches exactly |
| Governor limits exceeded | Not bulkified | Follow bulkification patterns above |
| Async action doesn't run | IAsyncTriggerAction not implemented | Implement both execute() and executeAsync() |

---

## Deployment Guide

### Step 1: Deploy Framework Classes

Copy these folders to your org's `force-app/main/default/` directory:
- `classes/` (all framework and test classes)
- `objects/Trigger_Action__mdt/` (Custom Metadata Type definition)
- `layouts/` (Custom Metadata layout)

Deploy using Salesforce CLI:
```bash
sf project deploy start --source-dir force-app/main/default
```

### Step 2: Create Triggers

For each standard or custom object, create a trigger:

```apex
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    TriggerDispatcher.dispatch('Account');
}
```

### Step 3: Create Action Classes

Implement your business logic in action classes (see examples above).

### Step 4: Register Actions

Create `Trigger_Action__mdt` records in Setup:
1. Go to **Setup → Custom Metadata Types → Trigger Action → Manage Records**
2. Click **New**
3. Fill in the fields according to the pattern shown in examples
4. Save

Or deploy metadata records via XML:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Account_AfterUpdate_StatusNotification</label>
    <protected>false</protected>
    <values>
        <field>Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>Class_Name__c</field>
        <value xsi:type="xsd:string">AccountStatusChangeNotification</value>
    </values>
    <values>
        <field>Context__c</field>
        <value xsi:type="xsd:string">AFTER_UPDATE</value>
    </values>
    <values>
        <field>Max_Recursion__c</field>
        <value xsi:type="xsd:double">1.0</value>
    </values>
    <values>
        <field>Order__c</field>
        <value xsi:type="xsd:double">20.0</value>
    </values>
    <values>
        <field>SObject__c</field>
        <value xsi:type="xsd:string">Account</value>
    </values>
</CustomMetadata>
```

### Step 5: Test

Run all tests to ensure 75%+ code coverage:
```bash
sf apex run test --test-level RunLocalTests --wait 10
```

---

## Troubleshooting

### Q: My action isn't firing at all

**Checklist:**
1. ✅ Is the trigger created for your object?
2. ✅ Is the Trigger_Action__mdt record created?
3. ✅ Is `Active__c = true`?
4. ✅ Does `Class_Name__c` exactly match your class name (case-sensitive)?
5. ✅ Is `Context__c` the correct trigger context?
6. ✅ Does your class implement `ITriggerAction`?
7. ✅ Is the class deployed to the org?

**Debug:**
```apex
// Add this to your trigger temporarily
System.debug('Trigger fired: ' + Trigger.operationType);
System.debug('Record count: ' + Trigger.size);
```

### Q: My async action's executeAsync() never runs

**Checklist:**
1. ✅ Does your class implement `IAsyncTriggerAction` (not just `ITriggerAction`)?
2. ✅ Are you in a context that allows Queueable? (not in future/batch/queueable already)
3. ✅ Check "Apex Jobs" in Setup to see if job was enqueued

### Q: I'm hitting governor limits

**Solutions:**
- Ensure your action is bulkified (no SOQL/DML in loops)
- Use `ctx.getChangedRecords()` to filter records early
- Consider splitting logic into multiple actions
- Use async actions for heavy processing
- Add conditional logic to skip unnecessary processing

### Q: How do I temporarily disable an action?

Set `Active__c = false` in the Custom Metadata record. No code deployment needed!

### Q: Can I control which actions run based on user profile?

Yes! Add custom logic in your action:

```apex
public void execute(TriggerContext ctx) {
    // Skip for system admin
    if (UserInfo.getProfileId() == SYSTEM_ADMIN_PROFILE_ID) {
        return;
    }
    
    // Your logic here
}
```

Or use Custom Settings/Custom Permissions for more flexibility.

---

## Real-World Examples

### Example 1: Opportunity Stage Change Tracking

**Use Case:** Automatically create a renewal opportunity when an opportunity is closed won.

**Logic:** 
- Trigger on: `AFTER_UPDATE` context
- Filter: Only process records where `StageName` field changed (using single field detection)
- Action: For opportunities that moved TO 'Closed Won' (regardless of previous stage), create a renewal opportunity

**Key Methods Used:**
- `ctx.getChangedRecords(Opportunity.StageName)` - Returns records where StageName changed
- `ctx.getOldValue(record, field)` - Gets the previous value to check transition direction

```apex
public class OpportunityClosedWonHandler implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        // Only process records where Stage changed to 'Closed Won'
        List<Opportunity> renewalOpps = new List<Opportunity>();
        
        for (SObject record : ctx.getChangedRecords(Opportunity.StageName)) {
            Opportunity newOpp = (Opportunity) record;
            String oldStage = (String) ctx.getOldValue(newOpp, Opportunity.StageName);
            
            if (newOpp.StageName == 'Closed Won' && oldStage != 'Closed Won') {
                renewalOpps.add(new Opportunity(
                    Name = newOpp.Name + ' - Renewal',
                    AccountId = newOpp.AccountId,
                    StageName = 'Prospecting',
                    CloseDate = newOpp.CloseDate.addYears(1),
                    Amount = newOpp.Amount,
                    Type = 'Renewal'
                ));
            }
        }
        
        if (!renewalOpps.isEmpty()) {
            insert renewalOpps;
        }
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Opportunity_AfterUpdate_ClosedWonHandler` |
| SObject__c | `Opportunity` |
| Context__c | `AFTER_UPDATE` |
| Class_Name__c | `OpportunityClosedWonHandler` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

### Example 2: Contact Address Synchronization

**Use Case:** Keep contact mailing addresses synchronized with their account's billing address when the account address is updated.

**Logic:**
- Trigger on: `AFTER_UPDATE` context on Account
- Filter: Only process accounts where ANY of the billing address fields changed (OR logic)
  - `BillingStreet` OR `BillingCity` OR `BillingState` OR `BillingPostalCode` OR `BillingCountry`
- Action: Update related contacts that have `Sync_Address_With_Account__c = true`

**Key Methods Used:**
- `ctx.getChangedRecords(List<SObjectField>)` - Returns records where ANY field in the list changed (OR logic)
- Example: If only BillingCity changed, the account is included. If both BillingCity AND BillingState changed, account is still included (needs at least one)

```apex
public class ContactSyncMailingAddress implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        // Get accounts where billing address fields changed
        List<SObjectField> addressFields = new List<SObjectField>{
            Account.BillingStreet,
            Account.BillingCity,
            Account.BillingState,
            Account.BillingPostalCode,
            Account.BillingCountry
        };
        
        List<SObject> changedAccounts = ctx.getChangedRecords(addressFields);
        
        if (changedAccounts.isEmpty()) {
            return;
        }
        
        // Get account IDs
        Set<Id> accountIds = new Set<Id>();
        for (SObject record : changedAccounts) {
            accountIds.add(record.Id);
        }
        
        // Query contacts that should be synced
        List<Contact> contacts = [
            SELECT Id, AccountId, MailingStreet, MailingCity, 
                   MailingState, MailingPostalCode, MailingCountry,
                   Sync_Address_With_Account__c
            FROM Contact
            WHERE AccountId IN :accountIds
            AND Sync_Address_With_Account__c = true
        ];
        
        // Update contact addresses
        Map<Id, Account> accountMap = new Map<Id, Account>();
        for (SObject record : changedAccounts) {
            accountMap.put(record.Id, (Account) record);
        }
        
        for (Contact con : contacts) {
            Account acc = accountMap.get(con.AccountId);
            con.MailingStreet = acc.BillingStreet;
            con.MailingCity = acc.BillingCity;
            con.MailingState = acc.BillingState;
            con.MailingPostalCode = acc.BillingPostalCode;
            con.MailingCountry = acc.BillingCountry;
        }
        
        if (!contacts.isEmpty()) {
            update contacts;
        }
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Account_AfterUpdate_ContactSyncMailingAddress` |
| SObject__c | `Account` |
| Context__c | `AFTER_UPDATE` |
| Class_Name__c | `ContactSyncMailingAddress` |
| Order__c | `20` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

### Example 3: Lead Assignment with Multiple Criteria

**Use Case:** Automatically assign qualified leads to the appropriate team based on their characteristics.

**Logic:**
- Trigger on: `BEFORE_UPDATE` context on Lead (before context allows direct field modification)
- Filter: Complex boolean logic using custom conditions
  - `(Status changed to 'Qualified')` **AND** `(Industry changed OR AnnualRevenue changed)`
- Action: Assign to different queues based on revenue and industry
  - Enterprise Team: Annual Revenue > $1M
  - Tech Team: Industry = 'Technology'
  - Standard Team: All others

**Key Methods Used:**
- `ctx.hasChanged(record, field)` - Check individual field changes
- Custom boolean logic combining multiple conditions with AND/OR operators
- Direct field modification on trigger records (works in before context)
- Example scenarios:
  - Status changes to Qualified AND Industry changes → Assigned
  - Status changes to Qualified AND Revenue changes → Assigned
  - Status changes to Qualified BUT neither Industry nor Revenue changed → NOT assigned
  - Industry changes BUT Status is not Qualified → NOT assigned

```apex
public class LeadAutoAssignment implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        // Assign when: Status changed to 'Qualified' AND (Industry changed OR Annual Revenue changed)
        List<Lead> leadsToAssign = new List<Lead>();
        
        for (SObject record : ctx.newList) {
            Lead newLead = (Lead) record;
            
            // Check if Status changed to Qualified
            Boolean statusChangedToQualified = 
                ctx.hasChanged(newLead, Lead.Status) && 
                newLead.Status == 'Qualified';
            
            // Check if Industry or Annual Revenue changed
            Boolean criteriaChanged = 
                ctx.hasChanged(newLead, Lead.Industry) || 
                ctx.hasChanged(newLead, Lead.AnnualRevenue);
            
            if (statusChangedToQualified && criteriaChanged) {
                // Assign based on criteria
                if (newLead.AnnualRevenue != null && newLead.AnnualRevenue > 1000000) {
                    newLead.OwnerId = getEnterpriseTeamQueue();
                } else if (newLead.Industry == 'Technology') {
                    newLead.OwnerId = getTechTeamQueue();
                } else {
                    newLead.OwnerId = getStandardQueue();
                }
                
                leadsToAssign.add(newLead);
            }
        }
        
        System.debug('Assigned ' + leadsToAssign.size() + ' leads');
    }
    
    private Id getEnterpriseTeamQueue() {
        // Implementation to get Queue ID
        return null;
    }
    
    private Id getTechTeamQueue() {
        // Implementation to get Queue ID
        return null;
    }
    
    private Id getStandardQueue() {
        // Implementation to get Queue ID
        return null;
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Lead_BeforeUpdate_AutoAssignment` |
| SObject__c | `Lead` |
| Context__c | `BEFORE_UPDATE` |
| Class_Name__c | `LeadAutoAssignment` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

### Example 4: Case Escalation with Field Tracking

**Use Case:** Automatically escalate cases and send notifications when priority is increased.

**Logic:**
- Trigger on: `AFTER_UPDATE` context on Case
- Filter: Only process records where `Priority` field changed (using single field detection)
- Validation: Check that priority actually increased (not just changed)
  - Uses custom ranking: Low=1, Medium=2, High=3
  - Only escalates if new rank > old rank
- Action: Set `IsEscalated = true` and send email notification

**Key Methods Used:**
- `ctx.getChangedRecords(Case.Priority)` - Returns records where Priority changed
- `ctx.getOldValue(record, field)` - Gets previous priority value
- Custom helper method `isPriorityIncrease()` to validate direction of change
- Example scenarios:
  - Low → Medium: Escalated ✓
  - Low → High: Escalated ✓
  - High → Low: NOT escalated (decrease)
  - Medium → Medium: NOT escalated (no change)

```apex
public class CaseEscalationHandler implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        List<Case> casesToEscalate = new List<Case>();
        
        for (SObject record : ctx.getChangedRecords(Case.Priority)) {
            Case newCase = (Case) record;
            String oldPriority = (String) ctx.getOldValue(newCase, Case.Priority);
            String newPriority = newCase.Priority;
            
            // Check if priority increased (Low->Medium, Medium->High, Low->High)
            if (isPriorityIncrease(oldPriority, newPriority)) {
                newCase.IsEscalated = true;
                casesToEscalate.add(newCase);
                
                // Send notification
                sendEscalationEmail(newCase, oldPriority, newPriority);
            }
        }
        
        System.debug('Escalated ' + casesToEscalate.size() + ' cases');
    }
    
    private Boolean isPriorityIncrease(String oldPriority, String newPriority) {
        Map<String, Integer> priorityRank = new Map<String, Integer>{
            'Low' => 1,
            'Medium' => 2,
            'High' => 3
        };
        
        Integer oldRank = priorityRank.get(oldPriority);
        Integer newRank = priorityRank.get(newPriority);
        
        return newRank != null && oldRank != null && newRank > oldRank;
    }
    
    private void sendEscalationEmail(Case c, String oldPriority, String newPriority) {
        // Email notification logic
        System.debug('Case ' + c.CaseNumber + ' escalated from ' + 
                     oldPriority + ' to ' + newPriority);
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Case_AfterUpdate_EscalationHandler` |
| SObject__c | `Case` |
| Context__c | `AFTER_UPDATE` |
| Class_Name__c | `CaseEscalationHandler` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

### Example 5: Async Data Enrichment

**Use Case:** Enrich account data by calling an external API without blocking the user's transaction.

**Logic:**
- Trigger on: `AFTER_INSERT` context on Account
- Synchronous phase (`execute`): 
  - Validate that `Website` field is populated (required for enrichment)
  - Add error if missing, preventing insert
- Asynchronous phase (`executeAsync`):
  - Runs in Queueable context (separate transaction)
  - Queries accounts and calls external enrichment API
  - Updates Industry, NumberOfEmployees, and AnnualRevenue
  - Includes error handling for API failures

**Key Concepts:**
- Implements `IAsyncTriggerAction` interface
- Framework automatically enqueues async actions after sync actions complete
- Async execution has separate governor limits
- No field change detection needed (all new records processed)
- Example: User inserts account → validation runs immediately → user sees success → enrichment happens in background

```apex
public class AccountDataEnrichment implements IAsyncTriggerAction {
    public void execute(TriggerContext ctx) {
        // Sync validation - ensure required fields are present
        for (SObject record : ctx.newList) {
            Account acc = (Account) record;
            if (String.isBlank(acc.Website)) {
                acc.Website.addError('Website is required for data enrichment');
            }
        }
    }
    
    public void executeAsync(Set<Id> recordIds) {
        // Query accounts
        List<Account> accounts = [
            SELECT Id, Name, Website, Industry, NumberOfEmployees
            FROM Account 
            WHERE Id IN :recordIds
        ];
        
        // Call external service for each account
        for (Account acc : accounts) {
            try {
                // Mock external API call
                Map<String, Object> enrichedData = callEnrichmentAPI(acc.Website);
                
                // Update account with enriched data
                if (enrichedData.containsKey('industry')) {
                    acc.Industry = (String) enrichedData.get('industry');
                }
                if (enrichedData.containsKey('employeeCount')) {
                    acc.NumberOfEmployees = (Integer) enrichedData.get('employeeCount');
                }
                if (enrichedData.containsKey('annualRevenue')) {
                    acc.AnnualRevenue = (Decimal) enrichedData.get('annualRevenue');
                }
                
            } catch (Exception e) {
                System.debug('Failed to enrich account ' + acc.Id + ': ' + e.getMessage());
            }
        }
        
        // Update accounts
        update accounts;
    }
    
    private Map<String, Object> callEnrichmentAPI(String website) {
        // Mock implementation
        // In production, this would call an external API
        return new Map<String, Object>{
            'industry' => 'Technology',
            'employeeCount' => 500,
            'annualRevenue' => 10000000
        };
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Account_AfterInsert_DataEnrichment` |
| SObject__c | `Account` |
| Context__c | `AFTER_INSERT` |
| Class_Name__c | `AccountDataEnrichment` |
| Order__c | `50` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

### Example 6: Before Delete Validation

**Use Case:** Prevent users from deleting accounts that have open (not closed) opportunities.

**Logic:**
- Trigger on: `BEFORE_DELETE` context on Account
- Filter: All records being deleted (uses `ctx.oldList` since there's no newList in delete)
- Validation: 
  - Query aggregate to count open opportunities per account
  - Add error to account if it has open opportunities
  - Error message includes opportunity count
- Result: Delete operation is blocked with user-friendly error message

**Key Concepts:**
- Before context allows adding errors to prevent DML operation
- Uses `ctx.oldList` (not newList) since records are being deleted
- Aggregate query for performance (count only, no individual records)
- Error added via `record.addError()` stops the entire transaction
- Example: User tries to delete account with 3 open opps → Error: "Cannot delete account with 3 open opportunities..."

```apex
public class AccountPreventDeleteWithOpportunities implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        // Get account IDs being deleted
        Set<Id> accountIds = new Map<Id, SObject>(ctx.oldList).keySet();
        
        // Query for related opportunities
        Map<Id, Integer> accountOppCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT AccountId, COUNT(Id) oppCount
            FROM Opportunity
            WHERE AccountId IN :accountIds
            AND IsClosed = false
            GROUP BY AccountId
        ]) {
            accountOppCounts.put(
                (Id) ar.get('AccountId'),
                (Integer) ar.get('oppCount')
            );
        }
        
        // Add errors to accounts with open opportunities
        for (SObject record : ctx.oldList) {
            Account acc = (Account) record;
            Integer oppCount = accountOppCounts.get(acc.Id);
            
            if (oppCount != null && oppCount > 0) {
                acc.addError(
                    'Cannot delete account with ' + oppCount + 
                    ' open opportunities. Please close or reassign them first.'
                );
            }
        }
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Account_BeforeDelete_PreventWithOpportunities` |
| SObject__c | `Account` |
| Context__c | `BEFORE_DELETE` |
| Class_Name__c | `AccountPreventDeleteWithOpportunities` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

### Example 7: After Undelete Recovery

**Use Case:** Automatically restore related opportunities and contacts when an account is undeleted from the recycle bin.

**Logic:**
- Trigger on: `AFTER_UNDELETE` context on Account
- Filter: All undeleted accounts (uses `ctx.newList` - the restored records)
- Action:
  - Query for deleted opportunities using `ALL ROWS` (includes recycle bin)
  - Query for deleted contacts using `ALL ROWS`
  - Undelete both related record types
- Result: Restores the data relationship graph when parent is recovered

**Key Concepts:**
- `AFTER_UNDELETE` only fires when records are restored from recycle bin
- Requires `ALL ROWS` in SOQL to include deleted records
- Can only undelete records that are in recycle bin (not hard-deleted)
- Restores relationships automatically
- Example: User undeletes Account → 5 deleted opportunities and 12 deleted contacts are automatically restored

```apex
public class AccountRestoreRelatedRecords implements ITriggerAction {
    public void execute(TriggerContext ctx) {
        Set<Id> accountIds = new Set<Id>();
        
        for (SObject record : ctx.newList) {
            accountIds.add(record.Id);
        }
        
        // Query for deleted opportunities
        List<Opportunity> deletedOpps = [
            SELECT Id
            FROM Opportunity
            WHERE AccountId IN :accountIds
            AND IsDeleted = true
            ALL ROWS
        ];
        
        // Undelete opportunities
        if (!deletedOpps.isEmpty()) {
            undelete deletedOpps;
            System.debug('Restored ' + deletedOpps.size() + ' opportunities');
        }
        
        // Query for deleted contacts
        List<Contact> deletedContacts = [
            SELECT Id
            FROM Contact
            WHERE AccountId IN :accountIds
            AND IsDeleted = true
            ALL ROWS
        ];
        
        // Undelete contacts
        if (!deletedContacts.isEmpty()) {
            undelete deletedContacts;
            System.debug('Restored ' + deletedContacts.size() + ' contacts');
        }
    }
}
```

**Custom Metadata Configuration:**
| Field | Value |
|-------|-------|
| Label | `Account_AfterUndelete_RestoreRelatedRecords` |
| SObject__c | `Account` |
| Context__c | `AFTER_UNDELETE` |
| Class_Name__c | `AccountRestoreRelatedRecords` |
| Order__c | `10` |
| Active__c | `true` |
| Max_Recursion__c | `1` |

---

## Examples Quick Reference

| Example | SObject | Context | Use Case | Pattern |
|---------|---------|---------|----------|---------|
| 1. Opportunity Stage Change | Opportunity | AFTER_UPDATE | Create renewal opportunities when deal closes | Single field change detection |
| 2. Contact Address Sync | Account | AFTER_UPDATE | Sync contact addresses when account address changes | Multiple field change (OR) + related record update |
| 3. Lead Auto Assignment | Lead | BEFORE_UPDATE | Assign leads based on status and criteria | Complex AND/OR logic |
| 4. Case Escalation | Case | AFTER_UPDATE | Escalate and notify on priority increase | Custom comparison logic |
| 5. Account Data Enrichment | Account | AFTER_INSERT | Enrich account data from external API | Async (IAsyncTriggerAction) |
| 6. Prevent Account Delete | Account | BEFORE_DELETE | Block deletion with open opportunities | Before delete validation |
| 7. Account Undelete Recovery | Account | AFTER_UNDELETE | Restore related records after undelete | After undelete with ALL ROWS |

---

## Multi-Package Architecture

### Base Package (Parent)
- All framework classes (Dispatcher, Executor, Context, etc.)
- Trigger_Action__mdt type definition
- Standard object triggers (Account, Contact, etc.)

### Extension Package (Child)
- Concrete action classes implementing ITriggerAction
- Trigger_Action__mdt records registering the actions
- Custom object triggers (if introducing new objects)

Extension packages depend on the base package. Custom Metadata records are **additive** across packages, so child packages register their actions without modifying the parent.

## Implementation Details

The framework follows a metadata-driven architecture where all trigger logic is registered via Custom Metadata records, enabling dynamic, package-aware trigger handling without code modifications.

## Available Trigger Contexts

The framework supports all standard Salesforce trigger contexts:
- `BEFORE_INSERT`
- `BEFORE_UPDATE`
- `BEFORE_DELETE`
- `AFTER_INSERT`
- `AFTER_UPDATE`
- `AFTER_DELETE`
- `AFTER_UNDELETE`

## Resources

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
