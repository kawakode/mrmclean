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
        var config = AppConfig()
        config.enabledDevTools = ["npm", "docker"]
        config.alertsEnabled = false
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
        var view: AnyView
        var size = NSSize(width: 860, height: 580)
        switch screen {
        case "settings":
            view = AnyView(SettingsView())
            size = NSSize(width: 470, height: 430)
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
        window.contentView = NSHostingView(rootView: view.environment(store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        print("UI_SMOKE_WINDOW=\(window.windowNumber)")
        fflush(stdout)
        app.run()
    }
}
