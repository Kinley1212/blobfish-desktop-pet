// Opening/restarting and changing topics are app requests, not user memories.
// Ordinary replies have no turn-count trigger; the model follows the conversation.
enum AIChatTurnIntent: String {
    case opening, reply, newTopic
}
