import Foundation

/// Lightweight monitoring is independent of the much slower category scan.
@MainActor
final class AutomationMonitor {
    static let shared = AutomationMonitor()
    private weak var store: Store?
    private var task: Task<Void, Never>?

    func bind(_ store: Store) {
        self.store = store
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.store?.backgroundTick()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
    }
}
