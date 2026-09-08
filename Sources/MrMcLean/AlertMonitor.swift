import Foundation

@MainActor
final class AlertMonitor {
    static let shared = AlertMonitor()

    private weak var store: Store?
    private var task: Task<Void, Never>?

    func bind(_ store: Store) {
        self.store = store
    }

    func reschedule() {
        task?.cancel()
        guard let store else { return }
        let seconds = max(0.25, store.config.scanIntervalHours) * 3600
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
                await self?.tick()
            }
        }
    }

    private func tick() async {
        guard let store, store.canStartOperation else { return }
        await store.scan()
    }
}
