import SwiftUI
import MrMcLeanCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertSettings()
                .tabItem { Label("Alerts", systemImage: "bell") }
            CleanerSettings()
                .tabItem { Label("Cleaners", systemImage: "wrench.and.screwdriver") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 470, height: 430)
    }
}

private struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @State private var loginItemOn = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItemOn },
                    set: { newValue in
                        do {
                            try LoginItem.set(newValue)
                            loginItemOn = newValue
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                ))
                if !LoginItem.isSupported {
                    Text("Available once the app runs from a built bundle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show icon in Dock", isOn: $store.config.showDockIcon)
                Toggle("Start with the window hidden", isOn: $store.config.launchMinimized)
            }
            Section("Background scan") {
                Picker("Scan the disk every", selection: $store.config.scanIntervalHours) {
                    Text("1 hour").tag(1.0)
                    Text("3 hours").tag(3.0)
                    Text("6 hours").tag(6.0)
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertSettings: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Enable storage alerts", isOn: $store.config.alertsEnabled)
                Picker("Silence repeats for", selection: $store.config.cooldownHours) {
                    Text("6 hours").tag(6.0)
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                    Text("3 days").tag(72.0)
                }
                Picker("Re-alert if it grows by", selection: $store.config.reAlertGrowthPercent) {
                    Text("2%").tag(2.0)
                    Text("5%").tag(5.0)
                    Text("10%").tag(10.0)
                }
            }
            Section("Threshold per category, as a share of the disk") {
                ForEach(Catalog.all.filter { $0.supportsAlerts }) { category in
                    thresholdRow(category)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!store.config.alertsEnabled)
    }

    private func thresholdRow(_ category: StorageCategory) -> some View {
        let binding = store.binding(for: category.id)
        let diskBytes = store.snapshot?.disk.totalBytes ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: binding.alertEnabled) {
                HStack {
                    Text(category.name)
                    Spacer()
                    if binding.wrappedValue.alertEnabled {
                        Text(thresholdLabel(binding.wrappedValue.thresholdPercent, diskBytes: diskBytes))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if binding.wrappedValue.alertEnabled {
                Slider(value: binding.thresholdPercent, in: 2...60, step: 1)
            }
        }
    }

    private func thresholdLabel(_ percent: Double, diskBytes: Int64) -> String {
        let base = "\(Int(percent))%"
        guard diskBytes > 0 else { return base }
        let bytes = Int64(Double(diskBytes) * percent / 100)
        return "\(base)  (\(Format.bytes(bytes)))"
    }
}

private struct CleanerSettings: View {
    @Environment(Store.self) private var store

    var body: some View {
        Form {
            Section {
                Toggle("Move non-cache items to the Trash instead of deleting", isOn: Binding(
                    get: { !store.config.hardDeleteNonCache },
                    set: { store.config.hardDeleteNonCache = !$0 }
                ))
                Text("Caches, logs and derived data are always deleted outright.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Detected dev tools") {
                ForEach(ToolCleaner.tools) { tool in
                    HStack {
                        Text(tool.name)
                        Spacer()
                        Text(store.detectedTools[tool.id] != nil ? "found" : "not found")
                            .font(.caption)
                            .foregroundStyle(store.detectedTools[tool.id] != nil ? .green : .secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                Text("MrMcLean \(version)").font(.headline)
                Text("A minimal storage cleaner with per-category size alerts. No third-party dependencies.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Safety") {
                Text("Every user-level deletion is checked against an allowlist. System paths, Documents, Desktop, Downloads, Photos and iCloud Drive are always rejected. The administrator step shows its exact script before running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
