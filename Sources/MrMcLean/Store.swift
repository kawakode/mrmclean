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
            if persistConfig { config.save() }
            if config.showDockIcon != oldValue.showDockIcon { applyActivationPolicy() }
            if config.scanIntervalHours != oldValue.scanIntervalHours {
                AlertMonitor.shared.reschedule()
            }
            if !config.automationEnabled && oldValue.automationEnabled { activeRuleTask?.cancel() }
            if config.alertsEnabled != oldValue.alertsEnabled
                || config.activityAlerts.map(\.monitoringConfig) != oldValue.activityAlerts.map(\.monitoringConfig) {
                activityTrackers = [:]
                monitorStatus = [:]
                lastMonitoringCheck = nil
            }
        }
    }
    var snapshot: ScanSnapshot?
    var scanning = false
    var progress: Double = 0
    var statusText = ""
    var banner: Banner?
    var largeFileScan: LargeFileScan?
    var largeFiles: [SizedEntry] { largeFileScan?.entries ?? [] }
    var cleaning = false
    var cleanupRequest: CleanupRequest?
    var isBusy: Bool { scanning || scanningLargeFiles || cleaning || fullCleanRunning || managingFiles }
    var canStartOperation: Bool { !isBusy && !showAccessGate && fullCleanReport == nil }
    var scanningLargeFiles = false
    var managingFiles = false
    var recentRuleActivity: [RuleReceipt] = []
    var ruleHistoryProblem: String?
    var lastRuleRun: Date?
    var ruleRunSummary = "Rules have not run this session."
    var monitorStatus: [UUID: String] = [:]
    var notificationStatus = ""

    @ObservationIgnored var ruleJournal = RuleJournal()
    @ObservationIgnored var activityTrackers: [UUID: ActivityTracker] = [:]
    @ObservationIgnored var lastMonitoringCheck: Date?
    @ObservationIgnored var activeRuleTask: Task<(RuleRunResult, RuleJournal), Never>?

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
    @ObservationIgnored private var started = false
    @ObservationIgnored let persistConfig: Bool
    @ObservationIgnored let diskOperationsEnabled: Bool

    /// True until the user grants access or explicitly continues without it.
    /// `.unknown` (no probe file to test) does not block.
    var showAccessGate: Bool {
        fullDiskAccess == .denied && !accessGateDismissed && fullCleanReport == nil
    }

    init(config: AppConfig = AppConfig.load(), detectedTools: [String: String] = ToolCleaner.detect(),
         fullDiskAccess: FullDiskAccessStatus = FullDiskAccess.check(), persistConfig: Bool = true,
         diskOperationsEnabled: Bool = true) {
        self.config = config
        self.detectedTools = detectedTools
        self.fullDiskAccess = fullDiskAccess
        self.persistConfig = persistConfig
        self.diskOperationsEnabled = diskOperationsEnabled
        if persistConfig {
            do {
                ruleJournal = try RuleJournal.load()
                recentRuleActivity = Array(ruleJournal.receipts.suffix(50).reversed())
            } catch { ruleHistoryProblem = "Execution history could not be loaded. Rules are paused: \(error.localizedDescription)" }
        }
        ready = true
    }

    // MARK: Lifecycle

    func startup() async {
        guard !started else { return }
        started = true
        NotificationsController.shared.bootstrap()
        AlertMonitor.shared.bind(self)
        AlertMonitor.shared.reschedule()
        applyActivationPolicy()
        if snapshot == nil { await scan() }
        AutomationMonitor.shared.bind(self)
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
        if fullDiskAccess != previous { applyActivationPolicy() }
        return previous != .granted && fullDiskAccess == .granted
    }

    func continueWithoutAccess() {
        accessGateDismissed = true
        applyActivationPolicy()
    }

    // MARK: Scanning

    func scan() async {
        guard canStartOperation, diskOperationsEnabled else { return }
        await refreshSnapshot()
    }

    private func refreshSnapshot() async {
        scanning = true
        progress = 0
        statusText = "Starting"
        var result = await Scanner.run { [weak self] fraction, name in
            Task { @MainActor in
                guard let self, self.scanning else { return }
                self.progress = fraction
                self.statusText = "Scanning \(name)"
            }
        }
        if let largeFileScan { result.recordLargeFiles(largeFileScan) }
        snapshot = result
        fullDiskAccess = result.fullDiskAccess
        scanning = false
        progress = 1
        applyActivationPolicy()
        statusText = ""
        if !cleaning && !fullCleanRunning { await evaluateAlerts() }
    }

    func scanLargeFiles() async {
        guard canStartOperation, diskOperationsEnabled else { return }
        scanningLargeFiles = true
        statusText = "Finding large files…"
        let result = await LargeFiles.scan()
        largeFileScan = result
        snapshot?.recordLargeFiles(result)
        statusText = ""
        scanningLargeFiles = false
    }

    // MARK: Cleaning

    func requestQuickClean() {
        guard canStartOperation, let snapshot, !snapshot.quickCleanEntries.isEmpty else { return }
        cleanupRequest = CleanupRequest(title: "Clean Caches & Logs", items: snapshot.quickCleanEntries,
                                        mode: .hardDelete)
    }

    func requestClean(category: StorageCategory, items: [SizedEntry]) {
        guard canStartOperation, !items.isEmpty else { return }
        cleanupRequest = CleanupRequest(title: "Clean \(category.name)", items: items,
            mode: Cleaner.mode(for: category, hardDeleteNonCache: config.hardDeleteNonCache))
    }

    func requestDevTools() {
        guard canStartOperation, !enabledDevToolIDs.isEmpty else { return }
        cleanupRequest = CleanupRequest(title: "Clean Dev Tools", items: [], mode: .hardDelete,
                                        toolIDs: enabledDevToolIDs)
    }

    func performCleanup(_ request: CleanupRequest) async {
        guard canStartOperation, diskOperationsEnabled else { return }
        cleaning = true
        defer { cleaning = false; statusText = "" }
        statusText = request.title
        if request.toolIDs.isEmpty {
            let outcome = await Task.detached {
                Cleaner.execute(items: request.items, mode: request.mode)
            }.value
            report(outcome)
        } else {
            let failures = await executeDevTools(request.toolIDs)
            banner = Banner(text: failures.isEmpty ? "Dev tool cleanup finished" : failures.joined(separator: "\n"),
                            kind: failures.isEmpty ? .success : .failure)
        }
        await refreshSnapshot()
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
                bytes += snapshot?.category(id)?.entries.reduce(0) { $0 + $1.bytes } ?? 0
            case .devTools:
                bytes += enabledDevToolBytes(excludingUserCaches: true)
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
        guard canStartOperation, snapshot != nil else { return }
        pendingFullCleanRequest = true
    }

    func dismissFullClean() {
        guard !fullCleanRunning else { return }
        fullCleanReport = nil
        applyActivationPolicy()
    }

    func performFullClean(includeSystem: Bool, includeSnapshots: Bool, reviewedScript: String?,
                          reviewedSnapshot: ScanSnapshot, devToolIDs: [String]) async {
        guard canStartOperation, diskOperationsEnabled, snapshot != nil, !includeSystem || reviewedScript != nil else { return }

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

        // Keep the reviewed scan stable. A new scan here could add unreviewed
        // items to a destructive operation.

        for step in steps {
            report.update(step.id) { $0.status = .running }
            fullCleanReport = report
            // A short beat so each phase is visible in the animation.
            try? await Task.sleep(for: .milliseconds(500))

            switch step.work {
            case .userCategory(let id):
                await runUserCategoryPhase(id, entries: reviewedSnapshot.category(id)?.entries ?? [], into: &report, stepID: step.id)
            case .devTools(let ids):
                await runDevToolsPhase(ids, into: &report, stepID: step.id)
            case .system(let snapshots):
                await runSystemPhase(includeSnapshots: snapshots, script: reviewedScript!, into: &report, stepID: step.id)
            }

            fullCleanReport = report
            try? await Task.sleep(for: .milliseconds(300))
        }

        await refreshSnapshot()
        report.diskAfter = snapshot?.disk ?? DiskInfo.current()
        report.finishedAt = Date()
        fullCleanReport = report
        fullCleanRunning = false
        await evaluateAlerts()
    }

    private func runUserCategoryPhase(_ id: String, entries: [SizedEntry], into report: inout FullCleanReport, stepID: String) async {
        guard let category = Catalog.category(id) else {
            report.update(stepID) { $0.status = .skipped }
            return
        }
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
            $0.status = outcome.failed.isEmpty ? .done : .failed
            if !outcome.failed.isEmpty {
                $0.note = "\(outcome.failed.count) skipped"
            }
        }
    }

    func enabledDevToolBytes(excludingUserCaches: Bool = false) -> Int64 {
        let userEntries = snapshot?.category("userCaches")?.entries ?? []
        return ToolCleaner.tools.filter { enabledDevToolIDs.contains($0.id) }.reduce(0) { total, tool in
            guard let directory = tool.cacheDirectory else { return total }
            let path = expandTilde(directory)
            if excludingUserCaches && userEntries.contains(where: {
                path == $0.path || path.hasPrefix($0.path + "/")
            }) { return total }
            return total + (snapshot?.category("devTools")?.entries.first { $0.path == path }?.bytes ?? 0)
        }
    }

    private func executeDevTools(_ ids: [String]) async -> [String] {
        var failures: [String] = []
        for id in ids {
            guard let tool = ToolCleaner.tools.first(where: { $0.id == id }),
                  let path = detectedTools[id] else {
                failures.append("\(id): tool is no longer available.")
                continue
            }
            statusText = "Running \(tool.name) cleanup"
            let result = await ToolCleaner.run(tool, binaryPath: path)
            if let failure = result.failureDescription { failures.append("\(tool.name): \(failure)") }
        }
        return failures
    }

    private func runDevToolsPhase(_ ids: [String], into report: inout FullCleanReport, stepID: String) async {
        let before = await ToolCleaner.cacheBytes(for: ids)
        let failures = await executeDevTools(ids)
        let after = await ToolCleaner.cacheBytes(for: ids)
        report.update(stepID) {
            $0.freedBytes = max(0, before - after)
            $0.status = failures.isEmpty ? .done : .failed
            $0.note = failures.isEmpty ? "\(ids.count) tool(s) completed" : failures.joined(separator: "\n")
        }
    }

    private func runSystemPhase(includeSnapshots: Bool, script: String, into report: inout FullCleanReport, stepID: String) async {
        let estimate = (snapshot?.category("systemCaches")?.totalBytes ?? 0)
            + (includeSnapshots ? (snapshot?.category("snapshots")?.totalBytes ?? 0) : 0)
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
        guard canStartOperation, diskOperationsEnabled else { return }
        cleaning = true
        statusText = "Cleaning system files"
        defer { cleaning = false; statusText = "" }
        do {
            try await AdminCleaner.run(script: script)
            banner = Banner(text: "System cleanup finished", kind: .success)
        } catch {
            banner = Banner(text: error.localizedDescription, kind: .failure)
        }
        await refreshSnapshot()
    }

    private func report(_ outcome: CleanOutcome) {
        if outcome.trashedBytes > 0 {
            let skipped = outcome.failed.isEmpty ? "" : " · \(outcome.failed.count) skipped"
            banner = Banner(text: "Moved \(Format.bytes(outcome.trashedBytes)) to Trash\(skipped). Empty the Trash to free space.",
                            kind: outcome.failed.isEmpty ? .success : .info)
        } else if outcome.freedBytes > 0 {
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

    func evaluateAlerts() async {
        guard let snapshot else { return }
        for scan in snapshot.categories where scan.category.supportsAlerts {
            let categoryConfig = config.category(scan.id)
            let evaluation = AlertLogic.evaluate(
                sizeBytes: scan.totalBytes,
                diskBytes: snapshot.disk.totalBytes,
                category: categoryConfig,
                global: config
            )
            guard evaluation.shouldNotify else { continue }
            let sent = await NotificationsController.shared.post(
                title: "\(scan.category.name) is large",
                body: "\(Format.bytes(scan.totalBytes)) is \(Format.percent(evaluation.fraction, digits: 1)) of this disk."
            )
            if sent, config.category(scan.id) == categoryConfig {
                config.categories[scan.id, default: CategoryConfig()].lastAlertDate = Date()
                config.categories[scan.id, default: CategoryConfig()].lastAlertBytes = scan.totalBytes
            }
        }
    }

    func binding(for id: String) -> Binding<CategoryConfig> {
        Binding(
            get: { self.config.categories[id] ?? CategoryConfig() },
            set: { self.config.categories[id] = $0 }
        )
    }
}
