/**
 * Interface for synchronous trigger action classes.
 * Each implementation represents a single, focused unit of trigger logic.
 */
public interface ITriggerAction {

    /**
     * Execute the trigger logic.
     * @param ctx The trigger context wrapper providing access to records and utilities.
     */
    void execute(TriggerContext ctx);
}