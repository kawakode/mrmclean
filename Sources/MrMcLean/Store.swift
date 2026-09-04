import AppKit
import Observation
import SwiftUI
import MrMcLeanCore

@MainActor
@Observable
final class Store {
    struct Banner: Identifiable, Equatable {
        enum Kind { case info, success, failure }
        let id = UUID()
        var text: String
        var kind: Kind
    }

    var config: AppConfig {
        didSet {
            guard ready, config != oldValue else { return }
            config.save()
            applyActivationPolicy()
            AlertMonitor.shared.reschedule()
        }
    }
    var snapshot: ScanSnapshot?
    var scanning = false
    var progress: Double = 0
    var statusText = ""
    var banner: Banner?
    var largeFiles: [SizedEntry] = []
    var scanningLargeFiles = false

    let detectedTools: [String: String]

    @ObservationIgnored private var ready = false

    init() {
        config = AppConfig.load()
        detectedTools = ToolCleaner.detect()
        ready = true
    }

    // MARK: Lifecycle

    func startup() async {
        NotificationsController.shared.bootstrap()
        AlertMonitor.shared.bind(self)
        AlertMonitor.shared.reschedule()
        applyActivationPolicy()
        if snapshot == nil { await scan() }
    }

    func applyActivationPolicy() {
        guard NSApp != nil else { return }
        NSApp.setActivationPolicy(config.showDockIcon ? .regular : .accessory)
    }

    // MARK: Scanning

    func scan() async {
        guard !scanning else { return }
        scanning = true
        progress = 0
        statusText = "Starting"
        let result = await Scanner.run { [weak self] fraction, name in
            Task { @MainActor in
                guard let self else { return }
                self.progress = fraction
                self.statusText = "Scanning \(name)"
            }
        }
        snapshot = result
        scanning = false
        statusText = ""
        evaluateAlerts()
    }

    func scanLargeFiles() async {
        guard !scanningLargeFiles else { return }
        scanningLargeFiles = true
        largeFiles = await LargeFiles.scan()
        scanningLargeFiles = false
    }

    // MARK: Cleaning

    func clean(categoryID: String, items: [SizedEntry]) async {
        guard let category = Catalog.category(categoryID), !items.isEmpty else { return }
        let mode = Cleaner.mode(for: category, hardDeleteNonCache: config.hardDeleteNonCache)
        statusText = "Cleaning \(category.name)"
        let outcome = await Task.detached { Cleaner.execute(items: items, mode: mode) }.value
        statusText = ""
        report(outcome)
        await scan()
    }

    func quickClean() async {
        guard let snapshot else { return }
        var items: [SizedEntry] = []
        for id in ["userCaches", "appLogs", "developer", "trash"] {
            items.append(contentsOf: snapshot.category(id)?.entries ?? [])
        }
        guard !items.isEmpty else { return }
        statusText = "Cleaning caches"
        let outcome = await Task.detached { Cleaner.execute(items: items, mode: .hardDelete) }.value
        statusText = ""
        report(outcome)
        await scan()
    }

    func runAdminClean(script: String) async {
        do {
            try await AdminCleaner.run(script: script)
            banner = Banner(text: "System cleanup finished", kind: .success)
            await scan()
        } catch {
            banner = Banner(text: error.localizedDescription, kind: .failure)
        }
    }

    func runDevTools(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard
                let tool = ToolCleaner.tools.first(where: { $0.id == id }),
                let path = detectedTools[id]
            else { continue }
            statusText = "Running \(tool.name) cleanup"
            _ = await ToolCleaner.run(tool, binaryPath: path)
        }
        statusText = ""
        banner = Banner(text: "Dev tool cleanup finished", kind: .success)
        await scan()
    }

    private func report(_ outcome: CleanOutcome) {
        if outcome.freedBytes > 0 {
            let skipped = outcome.failed.isEmpty ? "" : ", \(outcome.failed.count) skipped"
            banner = Banner(text: "Freed \(Format.bytes(outcome.freedBytes))\(skipped)",
                            kind: outcome.failed.isEmpty ? .success : .info)
        } else if !outcome.failed.isEmpty {
            banner = Banner(text: "Nothing removed, \(outcome.failed.count) item(s) skipped", kind: .failure)
        } else {
            banner = Banner(text: "Already clean", kind: .info)
        }
    }

    // MARK: Alerts

    func evaluateAlerts() {
        guard let snapshot else { return }
        var updated = config
        var changed = false
        for scan in snapshot.categories where scan.category.supportsAlerts {
            let categoryConfig = updated.category(scan.id)
            let evaluation = AlertLogic.evaluate(
                sizeBytes: scan.totalBytes,
                diskBytes: snapshot.disk.totalBytes,
                category: categoryConfig,
                global: updated
            )
            guard evaluation.shouldNotify else { continue }
            NotificationsController.shared.post(
                title: "\(scan.category.name) is large",
                body: "\(Format.bytes(scan.totalBytes)) is \(Format.percent(evaluation.fraction, digits: 1)) of this disk."
            )
            var categoryUpdated = categoryConfig
            categoryUpdated.lastAlertDate = Date()
            categoryUpdated.lastAlertBytes = scan.totalBytes
            updated.categories[scan.id] = categoryUpdated
            changed = true
        }
        if changed { config = updated }
    }

    func binding(for id: String) -> Binding<CategoryConfig> {
        Binding(
            get: { self.config.categories[id] ?? CategoryConfig() },
            set: { self.config.categories[id] = $0 }
        )
    }
}
