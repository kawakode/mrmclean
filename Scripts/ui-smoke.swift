// Compiled by ui-smoke.sh against the actual app views, with synthetic data.
// No scan, tool command, administrator action or cleanup is executed.
import AppKit
import SwiftUI
import MrMcLeanCore

@main
@MainActor
enum UISmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let screen = CommandLine.arguments.dropFirst().first ?? "overview"
        if screen == "automationChecks" {
            Task {
                do { try await automationChecks(); print("AUTOMATION_STORE_SMOKE_OK"); exit(0) }
                catch { print("AUTOMATION_STORE_SMOKE_FAILED: \(error)"); exit(1) }
            }
            app.run()
            return
        }
        var config = AppConfig()
        config.enabledDevTools = ["npm", "docker"]
        config.alertsEnabled = false
        var exampleRule = FileRule()
        exampleRule.name = "Organize downloaded PDFs"
        exampleRule.folder = NSHomeDirectory() + "/Downloads"
        exampleRule.actions = [FileAction(kind: .tag, value: "Reading"),
                               FileAction(kind: .move, value: NSHomeDirectory() + "/Documents", subfolder: "{year}/{month}")]
        var exampleAlert = ActivityAlertConfig()
        exampleAlert.name = "Example app logs"
        exampleAlert.folder = NSHomeDirectory() + "/Library/Logs/ExampleApp"
        exampleAlert.isEnabled = true
        config.fileRules = [exampleRule]
        config.activityAlerts = [exampleAlert]
        config.lowStorage.isEnabled = true
        let store = Store(config: config, detectedTools: ["npm": "/usr/bin/false", "docker": "/usr/bin/false"],
                          fullDiskAccess: .granted, persistConfig: false, diskOperationsEnabled: false)
        let disk = DiskInfo(totalBytes: 1_000_000_000_000, rawAvailable: 250_000_000_000, importantAvailable: 300_000_000_000)
        let categories = Catalog.all.map { category in
            let entries = (0..<8).map { index in
                SizedEntry(path: "/UI-fixture/\(category.id)/\(index)-An example file with a long descriptive name.dat",
                           bytes: Int64(8 - index) * 1_000_000_000)
            }
            return CategoryScan(category: category, totalBytes: entries.reduce(0) { $0 + $1.bytes },
                                entries: entries, itemCount: entries.count)
        }
        store.snapshot = ScanSnapshot(disk: disk, categories: categories, date: Date(), fullDiskAccess: .granted)
        precondition(store.canStartOperation)
        store.cleaning = true
        precondition(!store.canStartOperation)
        store.cleaning = false
        store.scanningLargeFiles = true
        precondition(!store.canStartOperation)
        store.scanningLargeFiles = false
        store.fullCleanRunning = true
        precondition(!store.canStartOperation)
        store.fullCleanRunning = false
        store.managingFiles = true
        precondition(!store.canStartOperation)
        store.managingFiles = false
        var view: AnyView
        var size = NSSize(width: 860, height: 580)
        switch screen {
        case "settings":
            view = AnyView(SettingsView())
            size = NSSize(width: 560, height: 600)
        case "alerts":
            store.config.alertsEnabled = true
            view = AnyView(AlertSettings())
            size = NSSize(width: 560, height: 600)
        case "fileRules":
            view = AnyView(FileRulesView())
        case "ruleEditor":
            view = AnyView(FileRuleEditor(rule: exampleRule))
            size = NSSize(width: 620, height: 720)
        case "activityEditor":
            view = AnyView(ActivityAlertEditor(alert: exampleAlert))
            size = NSSize(width: 560, height: 620)
        case "rulePreview":
            let file = FileMetadata(url: URL(fileURLWithPath: "/UI-fixture/Downloads/Report.pdf"), identity: "fixture", bytes: 2000,
                                    created: Date(), modified: Date())
            let preview = RulePreview(rule: exampleRule, files: [PlannedFile(file: file, actions: [.tag("Reading"),
                .move(URL(fileURLWithPath: "/UI-fixture/Documents/2026/09/Report.pdf"))])])
            view = AnyView(RulePreviewSheet(preview: preview))
            size = NSSize(width: 640, height: 520)
        case "gate":
            store.fullDiskAccess = .denied
            view = AnyView(FullDiskAccessGate())
        case "setup":
            view = AnyView(FullCleanSetupSheet())
            size = NSSize(width: 560, height: 540)
        case "review":
            view = AnyView(CleanupReviewSheet(request: CleanupRequest(title: "Clean Caches & Logs",
                items: categories[0].entries, mode: .hardDelete)))
            size = NSSize(width: 560, height: 480)
        case "report", "running":
            var report = FullCleanReport(phases: FullClean.plan(includeSystem: true, devToolIDs: ["npm", "docker"])
                .map { FullCleanPhase(id: $0.id, title: $0.title, symbol: $0.symbol) }, diskBefore: disk)
            for phase in report.phases {
                report.update(phase.id) { $0.status = .done; $0.freedBytes = 1_000_000; $0.removedCount = 4 }
            }
            report.update("system") {
                $0.status = screen == "report" ? .failed : .running
                $0.note = "Permission denied: one or more system files could not be removed. Review access and try again."
            }
            if screen == "report" { report.finishedAt = Date(); report.diskAfter = disk }
            store.fullCleanReport = report
            view = AnyView(FullCleanView())
        default:
            if let category = Catalog.category(screen) {
                view = AnyView(CategoryDetailView(category: category))
            } else {
                view = AnyView(RootView())
            }
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "MrMcLean UI Smoke — \(screen)"
        window.contentView = NSHostingView(rootView: view.environment(store).background(Color(nsColor: .windowBackgroundColor)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        print("UI_SMOKE_WINDOW=\(window.windowNumber)")
        fflush(stdout)
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let content = window.contentView,
                      let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
                do { try data.write(to: URL(fileURLWithPath: path)) }
                catch { print(error); exit(1) }
                print("UI_SMOKE_CAPTURE=\(path)")
                exit(0)
            }
        }
        app.run()
    }

    /// Exercises Store scheduling and busy guards using only disposable files.
    /// No startup, disk-category scans, notifications or real config persistence.
    static func automationChecks() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MrMcLean-store-checks-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func write(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: url.path)
            return url
        }
        let first = try write("first.txt")
        var rule = FileRule()
        rule.folder = root.path
        rule.conditions = [FileCondition(value: "txt")]
        rule.actions = [FileAction(kind: .rename, value: "handled-{name}.{ext}")]
        var config = AppConfig()
        config.alertsEnabled = false
        config.fileRules = [rule]
        let store = Store(config: config, detectedTools: [:], fullDiskAccess: .granted, persistConfig: false)
        await store.backgroundTick()
        precondition(fm.fileExists(atPath: first.path), "master switch must prevent changes")
        store.config.automationEnabled = true
        await store.backgroundTick()
        precondition(fm.fileExists(atPath: first.path), "disabled rule must prevent changes")
        store.config.fileRules[0].isEnabled = true
        store.lastRuleRun = nil
        await store.backgroundTick()
        precondition(!fm.fileExists(atPath: first.path), "enabled scheduled rule must run")
        precondition(store.recentRuleActivity.count == 1 && !store.isBusy, "activity and busy state must update")
        let second = try write("second.txt")
        await store.backgroundTick()
        precondition(fm.fileExists(atPath: second.path), "interval must prevent an immediate repeat")
        store.lastRuleRun = .distantPast
        store.scanning = true
        await store.backgroundTick()
        precondition(fm.fileExists(atPath: second.path), "disk scans must exclude automation")
        store.scanning = false
        store.fullDiskAccess = .denied
        await store.backgroundTick()
        precondition(fm.fileExists(atPath: second.path), "access gate must exclude automation")
        store.fullDiskAccess = .granted
        await store.backgroundTick()
        precondition(!fm.fileExists(atPath: second.path), "due rules resume when the operation guard clears")
        precondition(store.recentRuleActivity.count == 2, "handled files must not be renamed twice")
        let third = try write("third.txt")
        store.config.automationEnabled = false
        await store.runRules()
        precondition(fm.fileExists(atPath: third.path), "manual runs must also respect the master switch")

        var alert = ActivityAlertConfig()
        alert.folder = root.path
        alert.isEnabled = true
        alert.fileCountThreshold = 1
        alert.growthEnabled = false
        store.config.alertsEnabled = true
        store.config.activityAlerts = [alert]
        await store.checkMonitors()
        precondition(store.monitorStatus[alert.id]?.contains("Baseline") == true, "first check must record a baseline")
        _ = try write("new.log")
        await store.checkMonitors()
        precondition(store.monitorStatus[alert.id]?.contains("1 new file") == true, "folder bursts must reach the UI status")
        precondition(store.config.activityAlerts[0].lastAlertDate == nil, "undelivered notifications must not advance cooldown")
        store.config.alertsEnabled = false
        precondition(store.activityTrackers.isEmpty && store.monitorStatus.isEmpty, "disabling alerts must reset sampling")
    }
}
