import Foundation

/// Utility class for debouncing rapid function calls
/// Useful for search input, auto-save, and other scenarios where you want to delay execution until calls stabilize
final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval
    private let queue: DispatchQueue

    /// Initialize a debouncer
    /// - Parameters:
    ///   - delay: Time to wait in seconds before executing the action (default: 0.3)
    ///   - queue: DispatchQueue to run on (default: main)
    init(delay: TimeInterval = 0.3, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    /// Debounce an action
    /// - Parameter action: The closure to execute after the delay period
    func debounce(action: @escaping () -> Void) {
        // Cancel any pending work
        workItem?.cancel()

        // Create new work item
        let newWorkItem = DispatchWorkItem(block: action)
        workItem = newWorkItem

        // Schedule after delay
        queue.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
    }

    /// Cancel any pending debounced action
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
