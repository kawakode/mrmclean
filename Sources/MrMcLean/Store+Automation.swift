import Foundation
import MrMcLeanCore

extension Store {
    func backgroundTick() async {
        guard canStartOperation, cleanupRequest == nil, diskOperationsEnabled else { return }
        let interval = max(30, min(60, config.monitoringIntervalSeconds))
        if lastMonitoringCheck.map({ Date().timeIntervalSince($0) >= interval }) ?? true {
            await checkMonitors()
        }
        guard canStartOperation, config.automationEnabled else { return }
        if lastRuleRun.map({ Date().timeIntervalSince($0) >= max(1, config.ruleIntervalMinutes) * 60 }) ?? true {
            await runRules()
        }
    }

    func previewRule(_ rule: FileRule) async -> RulePreview? {
        guard canStartOperation, diskOperationsEnabled else { return nil }
        managingFiles = true
        statusText = "Previewing \(rule.name)…"
        defer { managingFiles = false; statusText = "" }
        let journal = ruleJournal
        return await Task.detached { RuleEngine.preview(rule: rule, journal: journal) }.value
    }

    /// Manual runs also require the master switch and enabled rules. The same
    /// engine, scoping and history apply to scheduled and user-triggered runs.
    func runRules() async {
        guard canStartOperation, diskOperationsEnabled, config.automationEnabled,
              ruleHistoryProblem == nil else { return }
        managingFiles = true
        defer { managingFiles = false; statusText = "" }
        let rules = config.fileRules.filter(\.isEnabled)
        var total = RuleRunResult()
        var claimed = Set<String>()
        for rule in rules {
            guard config.automationEnabled, config.fileRules.contains(rule), !Task.isCancelled else { break }
            statusText = "Applying \(rule.name)…"
            let history = ruleJournal
            var preview = await Task.detached { RuleEngine.preview(rule: rule, journal: history) }.value
            guard config.automationEnabled, config.fileRules.contains(rule) else { continue }
            // Rules run in displayed order; one file is acted on by at most one rule per pass.
            preview.files.removeAll { claimed.contains($0.file.identity) }
            claimed.formUnion(preview.files.map { $0.file.identity })
            let plan = preview
            let persist = persistConfig
            let task = Task.detached {
                var journal = history
                let outcome = RuleEngine.execute(plan, journal: &journal, persist: {
                    if persist { try $0.save() }
                })
                return (outcome, journal)
            }
            activeRuleTask = task
            let (outcome, journal) = await task.value
            activeRuleTask = nil
            ruleJournal = journal
            recentRuleActivity = Array(journal.receipts.suffix(50).reversed())
            total.completed += outcome.completed
            total.issues += outcome.issues.map { "\(rule.name): \($0)" }
            if let failure = outcome.historyFailure { ruleHistoryProblem = failure; break }
        }
        lastRuleRun = Date()
        ruleRunSummary = "\(total.completed) file(s) handled" + (total.issues.isEmpty ? "." : "; \(total.issues.count) issue(s).")
        if !total.issues.isEmpty {
            banner = Banner(text: total.issues.joined(separator: "\n"), kind: .failure)
        } else if total.completed > 0 {
            banner = Banner(text: ruleRunSummary, kind: .success)
        }
    }

    func checkMonitors() async {
        guard canStartOperation, diskOperationsEnabled else { return }
        managingFiles = true
        statusText = "Checking storage alerts…"
        defer { managingFiles = false; statusText = ""; lastMonitoringCheck = Date() }
        notificationStatus = await NotificationsController.shared.authorizationDescription()
        guard config.alertsEnabled else {
            activityTrackers = [:]
            monitorStatus = [:]
            return
        }
        if config.lowStorage.isEnabled {
            let lowStorage = config.lowStorage
            let disk = await Task.detached { DiskInfo.current() }.value
            if config.lowStorage == lowStorage,
               lowStorage.shouldNotify(disk: disk, alertsEnabled: config.alertsEnabled, cooldownHours: config.cooldownHours) {
                let sent = await NotificationsController.shared.post(title: "Low storage",
                    body: "Only \(Format.bytes(disk.availableBytes)) is available (\(Format.percent(1 - disk.usedFraction, digits: 1)) of this disk).")
                if sent, config.lowStorage == lowStorage { config.lowStorage.lastAlertDate = Date() }
            }
        }
        let alerts = config.activityAlerts.filter(\.isEnabled)
        let enabledIDs = Set(alerts.map(\.id))
        activityTrackers = activityTrackers.filter { enabledIDs.contains($0.key) }
        monitorStatus = monitorStatus.filter { enabledIDs.contains($0.key) }
        for alert in alerts {
            guard config.alertsEnabled, config.activityAlerts.contains(alert) else { continue }
            let scan = await Task.detached { ManagedFiles.scan(folder: alert.folder, recursive: alert.includesSubfolders, readOnly: true) }.value
            guard config.alertsEnabled, config.activityAlerts.contains(alert) else { continue }
            var tracker = activityTrackers[alert.id] ?? ActivityTracker()
            let evaluation = tracker.observe(scan, config: alert, alertsEnabled: config.alertsEnabled,
                                             cooldownHours: config.cooldownHours)
            activityTrackers[alert.id] = tracker
            if let error = alert.validationError {
                monitorStatus[alert.id] = error
            } else if !scan.issues.isEmpty {
                monitorStatus[alert.id] = scan.issues.joined(separator: "\n")
            } else if let evaluation {
                monitorStatus[alert.id] = "\(evaluation.newFiles) new file(s), \(Format.bytes(evaluation.growthBytes)) added in the last \(Int(alert.windowMinutes)) min."
                if evaluation.shouldNotify {
                    let sent = await NotificationsController.shared.post(title: "Unusual file activity: \(alert.name)",
                        body: "\(evaluation.newFiles) new file(s) and \(Format.bytes(evaluation.growthBytes)) added within \(Int(alert.windowMinutes)) minutes in \(alert.folder).")
                    if sent, let index = config.activityAlerts.firstIndex(where: { $0 == alert }) {
                        config.activityAlerts[index].lastAlertDate = Date()
                    }
                }
            } else { monitorStatus[alert.id] = "Baseline recorded. Watching for new files and growth…" }
        }
    }
}
