/**
 * Queueable that executes async trigger actions after the transaction commits.
 */
public class TriggerAsyncQueueable implements Queueable {

    private List<IAsyncTriggerAction> actions;
    private Set<Id> recordIds;

    public TriggerAsyncQueueable(List<IAsyncTriggerAction> actions, Set<Id> recordIds) {
        this.actions   = actions;
        this.recordIds = recordIds;
    }

    public void execute(QueueableContext qc) {
        for (IAsyncTriggerAction action : this.actions) {
            action.executeAsync(this.recordIds);
        }
    }
}