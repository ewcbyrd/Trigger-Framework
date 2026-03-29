/**
 * Wrapper around Trigger context variables.
 * Provides field change detection utilities and is injectable for testing.
 */
public class TriggerContext {

    // -- Properties --
    public System.TriggerOperation operationType { get; private set; }
    public List<SObject> newList                 { get; private set; }
    public Map<Id, SObject> newMap               { get; private set; }
    public List<SObject> oldList                 { get; private set; }
    public Map<Id, SObject> oldMap               { get; private set; }
    public Boolean isBefore                      { get; private set; }
    public Boolean isAfter                       { get; private set; }
    public Boolean isInsert                      { get; private set; }
    public Boolean isUpdate                      { get; private set; }
    public Boolean isDelete                      { get; private set; }
    public Boolean isUndelete                    { get; private set; }
    public Integer size                          { get; private set; }

    /**
     * Production constructor -- reads from Trigger.* context.
     */
    public TriggerContext() {
        this.operationType = Trigger.operationType;
        this.newList       = Trigger.new;
        this.newMap        = Trigger.newMap;
        this.oldList       = Trigger.old;
        this.oldMap        = Trigger.oldMap;
        this.isBefore      = Trigger.isBefore;
        this.isAfter       = Trigger.isAfter;
        this.isInsert      = Trigger.isInsert;
        this.isUpdate      = Trigger.isUpdate;
        this.isDelete      = Trigger.isDelete;
        this.isUndelete    = Trigger.isUndelete;
        this.size          = Trigger.size;
    }

    /**
     * Test constructor -- allows injection of mock trigger context.
     */
    @TestVisible
    private TriggerContext(
        System.TriggerOperation operationType,
        List<SObject> newList,
        Map<Id, SObject> newMap,
        List<SObject> oldList,
        Map<Id, SObject> oldMap
    ) {
        this.operationType = operationType;
        this.newList       = newList;
        this.newMap        = newMap;
        this.oldList       = oldList;
        this.oldMap        = oldMap;
        this.isBefore      = operationType.name().startsWith('BEFORE');
        this.isAfter       = operationType.name().startsWith('AFTER');
        this.isInsert      = operationType.name().endsWith('INSERT');
        this.isUpdate      = operationType.name().endsWith('UPDATE');
        this.isDelete      = operationType.name().endsWith('DELETE');
        this.isUndelete    = operationType.name().endsWith('UNDELETE');
        this.size          = newList != null ? newList.size() : oldList != null ? oldList.size() : 0;
    }

    // -- Field Change Detection Helpers --

    /**
     * Returns true if the specified field value changed between old and new for the given record.
     * Always returns true for insert context (no old values).
     */
    public Boolean hasChanged(SObject record, SObjectField field) {
        if (this.oldMap == null) {
            return true;
        }
        SObject oldRecord = this.oldMap.get(record.Id);
        return oldRecord == null || record.get(field) != oldRecord.get(field);
    }

    /**
     * Returns true if ANY of the specified fields changed.
     */
    public Boolean hasChanged(SObject record, List<SObjectField> fields) {
        for (SObjectField field : fields) {
            if (this.hasChanged(record, field)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Returns the old value of a field for a given record.
     * Returns null if there is no old record (insert context).
     */
    public Object getOldValue(SObject record, SObjectField field) {
        if (this.oldMap == null) {
            return null;
        }
        SObject oldRecord = this.oldMap.get(record.Id);
        return oldRecord != null ? oldRecord.get(field) : null;
    }

    /**
     * Returns only the records where the specified field changed.
     */
    public List<SObject> getChangedRecords(SObjectField field) {
        List<SObject> changed = new List<SObject>();
        if (this.newList == null) {
            return changed;
        }
        for (SObject record : this.newList) {
            if (this.hasChanged(record, field)) {
                changed.add(record);
            }
        }
        return changed;
    }

    /**
     * Returns only the records where ANY of the specified fields changed.
     */
    public List<SObject> getChangedRecords(List<SObjectField> fields) {
        List<SObject> changed = new List<SObject>();
        if (this.newList == null) {
            return changed;
        }
        for (SObject record : this.newList) {
            if (this.hasChanged(record, fields)) {
                changed.add(record);
            }
        }
        return changed;
    }

    /**
     * Returns only the records where ALL of the specified fields changed.
     */
    public List<SObject> getChangedRecordsAll(List<SObjectField> fields) {
        List<SObject> changed = new List<SObject>();
        if (this.newList == null) {
            return changed;
        }
        for (SObject record : this.newList) {
            Boolean allChanged = true;
            for (SObjectField field : fields) {
                if (!this.hasChanged(record, field)) {
                    allChanged = false;
                    break;
                }
            }
            if (allChanged) {
                changed.add(record);
            }
        }
        return changed;
    }
}