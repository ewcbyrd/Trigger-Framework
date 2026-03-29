/**
 * Interface for trigger actions requiring asynchronous processing.
 * Extends ITriggerAction -- the sync execute() runs first,
 * then executeAsync() is enqueued as a Queueable.
 */
public interface IAsyncTriggerAction extends ITriggerAction {

    /**
     * Asynchronous logic executed via Queueable after the transaction commits.
     * @param recordIds The IDs of records from the trigger context.
     */
    void executeAsync(Set<Id> recordIds);
}