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

    /// Full Disk Access state, refreshed while the onboarding gate is on screen.
    var fullDiskAccess: FullDiskAccessStatus
    /// The user chose to run without Full Disk Access for this launch.
    var accessGateDismissed = false

    /// Live state of a full clean. Non-nil while the animated overlay is showing
    /// (during the run and afterwards as the report).
    var fullCleanReport: FullCleanReport?
    var fullCleanRunning = false
    /// Set by the menu bar / toolbar to ask the main window to open the setup sheet.
    var pendingFullCleanRequest = false

    let detectedTools: [String: String]

    @ObservationIgnored private var ready = false

    /// True until the user grants access or explicitly continues without it.
    /// `.unknown` (no probe file to test) does not block.
    var showAccessGate: Bool {
        fullDiskAccess == .denied && !accessGateDismissed && fullCleanReport == nil
    }

    init() {
        config = AppConfig.load()
        detectedTools = ToolCleaner.detect()
        fullDiskAccess = FullDiskAccess.check()
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
        // Keep a Dock icon while the access gate is up so the app is easy to find
        // when the user tabs back from System Settings.
        let regular = config.showDockIcon || showAccessGate
        NSApp.setActivationPolicy(regular ? .regular : .accessory)
    }

    // MARK: Full Disk Access

    /// Re-test the grant. Called on a timer while the onboarding gate is visible.
    /// Returns true when access just flipped to granted.
    @discardableResult
    func refreshAccess() -> Bool {
        let previous = fullDiskAccess
        fullDiskAccess = FullDiskAccess.check()
        return previous != .granted && fullDiskAccess == .granted
    }

    func continueWithoutAccess() {
        accessGateDismissed = true
        applyActivationPolicy()
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

    // MARK: Full clean

    /// Categories and totals a full clean would act on right now, for the setup sheet.
    func fullCleanPreview(includeSystem: Bool, includeSnapshots: Bool) -> (steps: [FullCleanStep], estimatedBytes: Int64) {
        let steps = FullClean.plan(includeSystem: includeSystem,
                                   includeSnapshots: includeSnapshots,
                                   devToolIDs: enabledDevToolIDs)
        var bytes: Int64 = 0
        for step in steps {
            switch step.work {
            case .userCategory(let id):
                bytes += snapshot?.category(id)?.totalBytes ?? 0
            case .devTools:
                bytes += snapshot?.category("devTools")?.totalBytes ?? 0
            case .system(let snapshots):
                bytes += snapshot?.category("systemCaches")?.totalBytes ?? 0
                if snapshots { bytes += snapshot?.category("snapshots")?.totalBytes ?? 0 }
            }
        }
        return (steps, bytes)
    }

    var enabledDevToolIDs: [String] {
        ToolCleaner.tools
            .map(\.id)
            .filter { config.enabledDevTools.contains($0) && detectedTools[$0] != nil }
    }

    func requestFullClean() {
        pendingFullCleanRequest = true
    }

    func dismissFullClean() {
        guard !fullCleanRunning else { return }
        fullCleanReport = nil
        applyActivationPolicy()
    }

    func performFullClean(includeSystem: Bool, includeSnapshots: Bool) async {
        guard !fullCleanRunning else { return }

        let devToolIDs = enabledDevToolIDs
        let steps = FullClean.plan(includeSystem: includeSystem,
                                   includeSnapshots: includeSnapshots,
                                   devToolIDs: devToolIDs)
        // Show the overlay right away with every phase pending.
        var report = FullCleanReport(
            phases: steps.map { FullCleanPhase(id: $0.id, title: $0.title, symbol: $0.symbol) },
            diskBefore: DiskInfo.current()
        )
        fullCleanReport = report
        fullCleanRunning = true
        applyActivationPolicy()

        // Refresh sizes: the per-phase figures and the disk baseline come from this.
        await scan()
        report.diskBefore = snapshot?.disk ?? report.diskBefore
        fullCleanReport = report

        for step in steps {
            report.update(step.id) { $0.status = .running }
            fullCleanReport = report
            // A short beat so each phase is visible in the animation.
            try? await Task.sleep(for: .milliseconds(500))

            switch step.work {
            case .userCategory(let id):
                await runUserCategoryPhase(id, into: &report, stepID: step.id)
            case .devTools(let ids):
                await runDevToolsPhase(ids, into: &report, stepID: step.id)
            case .system(let snapshots):
                await runSystemPhase(includeSnapshots: snapshots, into: &report, stepID: step.id)
            }

            fullCleanReport = report
            try? await Task.sleep(for: .milliseconds(300))
        }

        await scan()
        report.diskAfter = snapshot?.disk ?? DiskInfo.current()
        report.finishedAt = Date()
        fullCleanReport = report
        fullCleanRunning = false
        evaluateAlerts()
    }

    private func runUserCategoryPhase(_ id: String, into report: inout FullCleanReport, stepID: String) async {
        guard let category = Catalog.category(id) else {
            report.update(stepID) { $0.status = .skipped }
            return
        }
        let entries = snapshot?.category(id)?.entries ?? []
        guard !entries.isEmpty else {
            report.update(stepID) { $0.status = .done; $0.note = "Already clean" }
            return
        }
        let mode = Cleaner.mode(for: category, hardDeleteNonCache: config.hardDeleteNonCache)
        let outcome = await Task.detached { Cleaner.execute(items: entries, mode: mode) }.value
        report.update(stepID) {
            $0.freedBytes = outcome.freedBytes
            $0.removedCount = outcome.removed.count
            $0.skippedCount = outcome.failed.count
            $0.status = .done
            if !outcome.failed.isEmpty {
                $0.note = "\(outcome.failed.count) skipped"
            }
        }
    }

    private func runDevToolsPhase(_ ids: [String], into report: inout FullCleanReport, stepID: String) async {
        var estimate: Int64 = 0
        var ran = 0
        for id in ids {
            guard
                let tool = ToolCleaner.tools.first(where: { $0.id == id }),
                let path = detectedTools[id]
            else { continue }
            if let directory = tool.cacheDirectory {
                let expanded = expandTilde(directory)
                estimate += snapshot?.category("devTools")?.entries.first { $0.path == expanded }?.bytes ?? 0
            }
            _ = await ToolCleaner.run(tool, binaryPath: path)
            ran += 1
        }
        report.update(stepID) {
            $0.freedBytes = estimate
            $0.status = ran > 0 ? .done : .skipped
            $0.note = ran > 0 ? "\(ran) tool\(ran == 1 ? "" : "s") · estimated" : nil
        }
    }

    private func runSystemPhase(includeSnapshots: Bool, into report: inout FullCleanReport, stepID: String) async {
        let estimate = (snapshot?.category("systemCaches")?.totalBytes ?? 0)
            + (includeSnapshots ? (snapshot?.category("snapshots")?.totalBytes ?? 0) : 0)
        let script = await AdminCleaner.systemCleanScript(includeSnapshots: includeSnapshots)
        do {
            try await AdminCleaner.run(script: script)
            report.update(stepID) {
                $0.freedBytes = estimate
                $0.status = .done
                $0.note = "Estimated"
            }
        } catch {
            report.update(stepID) {
                $0.status = .failed
                $0.note = error.localizedDescription
            }
        }
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
