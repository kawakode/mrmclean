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
    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = AppConfig.load()
        // The onboarding gate needs the window up front (and a Dock icon so the
        // app is easy to return to from System Settings), whatever the saved
        // launch preference says.
        let needsAccess = FullDiskAccess.check() == .denied
        NSApp.setActivationPolicy(config.showDockIcon || needsAccess ? .regular : .accessory)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain && !(window is NSPanel) {
                if config.launchMinimized && !needsAccess {
                    window.close()
                } else {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.show()
        return true
    }
}

enum MainWindow {
    @MainActor
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain && !(window is NSPanel) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("MrMcLean.openMainWindow")
}
