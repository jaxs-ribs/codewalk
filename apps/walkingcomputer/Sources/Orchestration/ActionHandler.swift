import Foundation

/// Protocol for action handlers
protocol ActionHandler {
    func canHandle(_ action: ProposedAction) -> Bool
    func handle(_ action: ProposedAction) async

    /// Set a callback to receive real-time status updates during action execution
    func setStatusCallback(_ callback: @escaping @MainActor (String) -> Void)
}
