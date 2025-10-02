import Foundation

/// Protocol for action handlers
protocol ActionHandler {
    func canHandle(_ action: ProposedAction) -> Bool
    func handle(_ action: ProposedAction) async
}
