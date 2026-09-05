import SwiftUI
import AppKit
import MrMcLeanCore

@main
struct MrMcLeanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()

    var body: some Scene {
        Window("MrMcLean", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 860, minHeight: 580)
                .task { await store.startup() }
        }
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("MrMcLean", systemImage: "sparkles") {
            MenuBarView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by an explicit Quit before calling `NSApp.terminate` so the launch
    /// guard below lets it through.
    static var userWantsQuit = false
    private let launchedAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = AppConfig.load()
        let needsAccess = FullDiskAccess.check() == .denied

        // A menu bar app by default. Show a Dock icon when the user asked for one,
        // or while the Full Disk Access gate needs attention, so the window is
        // easy to get back to from System Settings.
        NSApp.setActivationPolicy(config.showDockIcon || needsAccess ? .regular : .accessory)

        if config.launchMinimized && !needsAccess {
            AppDelegate.hideMainWindow()
        } else {
            AppDelegate.presentMainWindow()
        }
    }

    /// The menu bar item is the app's home; closing the window must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// macOS 15+/26 SwiftUI fires one bogus terminate through the `MenuBarExtra`
    /// status-item scene a few hundred milliseconds after launch, which quit the
    /// app before its window ever appeared. Swallow terminate requests for the
    /// first few seconds unless the user explicitly asked to quit; Cmd-Q, the
    /// Quit item and logout all work normally after that.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.userWantsQuit || Date().timeIntervalSince(launchedAt) >= 4 {
            return .terminateNow
        }
        NSLog("MrMcLean: ignoring a launch-time terminate request (known MenuBarExtra issue)")
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.presentMainWindow()
        return true
    }

    /// Bring the main window to the front. The `Window` scene's `NSWindow` is
    /// frequently not in `NSApp.windows` on the first runloop pass, so retry for
    /// a short while until it materialises.
    @MainActor
    static func presentMainWindow(attemptsLeft: Int = 40) {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            presentMainWindow(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Close the window the `Window` scene opens at launch, for "start hidden".
    /// Retries briefly since the window may not exist on the first pass.
    @MainActor
    static func hideMainWindow(attemptsLeft: Int = 20) {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.close()
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            hideMainWindow(attemptsLeft: attemptsLeft - 1)
        }
    }
}

enum MainWindow {
    @MainActor
    static func show() {
        AppDelegate.presentMainWindow()
        // Belt and suspenders: also ask SwiftUI to (re)create the window in case
        // AppKit has none to order front.
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("MrMcLean.openMainWindow")
}
