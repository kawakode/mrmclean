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
        .frame(width: 560, height: 600)
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
                .disabled(!LoginItem.isSupported)
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

struct AlertSettings: View {
    @Environment(Store.self) private var store
    @State private var editingAlert: ActivityAlertConfig?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Enable alerts", isOn: $store.config.alertsEnabled)
                Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
                Button("Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
            Section("Low storage") {
                Toggle("Alert when available space is low", isOn: $store.config.lowStorage.isEnabled)
                if store.config.lowStorage.isEnabled {
                    HStack {
                        Text("Available space at or below")
                        Spacer()
                        TextField("Threshold", value: $store.config.lowStorage.threshold, format: .number)
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 65)
                        Picker("Unit", selection: $store.config.lowStorage.unit) {
                            Text("% of disk").tag(LowStorageConfig.Unit.percent)
                            Text("GB").tag(LowStorageConfig.Unit.gigabytes)
                        }.labelsHidden().frame(width: 110)
                    }
                    if store.config.lowStorage.threshold <= 0 || (store.config.lowStorage.unit == .percent && store.config.lowStorage.threshold > 100) {
                        Text("Enter a positive threshold (at most 100 for a percentage).").font(.caption).foregroundStyle(.red)
                    }
                    Text("Uses available space including storage macOS can reclaim.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!store.config.alertsEnabled)
            Section("App file activity") {
                Text("Watch an app’s logs or output folder for a burst of new files or rapid growth. The folder’s label identifies the app; writers are not detected automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.config.activityAlerts) { alert in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Toggle(alert.name, isOn: Binding(
                                get: { store.config.activityAlerts.first(where: { $0.id == alert.id })?.isEnabled ?? false },
                                set: { enabled in
                                    if let index = store.config.activityAlerts.firstIndex(where: { $0.id == alert.id }) {
                                        store.config.activityAlerts[index].isEnabled = enabled
                                    }
                                }))
                            Spacer()
                            Button("Edit") { editingAlert = alert }
                            Button(role: .destructive) { store.config.activityAlerts.removeAll { $0.id == alert.id } } label: {
                                Image(systemName: "trash")
                            }.help("Delete activity alert")
                        }
                        Text(alert.folder).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let status = store.monitorStatus[alert.id] {
                            Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                Button("Add Activity Alert…") { editingAlert = ActivityAlertConfig() }
                Picker("Check storage and activity every", selection: $store.config.monitoringIntervalSeconds) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                }
                Button("Check Now") { Task { await store.checkMonitors() } }
                    .disabled(!store.canStartOperation)
                Text("Checks run while the app is open. The first check records existing files; later checks detect changes. Files created and removed between checks can be missed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.config.alertsEnabled)
            Section("Repeat alerts") {
                Picker("Silence repeats for", selection: $store.config.cooldownHours) {
                    Text("6 hours").tag(6.0)
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                    Text("3 days").tag(72.0)
                }
                Picker("Category re-alert if it grows by", selection: $store.config.reAlertGrowthPercent) {
                    Text("2%").tag(2.0)
                    Text("5%").tag(5.0)
                    Text("10%").tag(10.0)
                }
            }
            .disabled(!store.config.alertsEnabled)
            Section("Threshold per category, as a share of the disk") {
                ForEach(Catalog.all.filter { $0.supportsAlerts }) { category in
                    thresholdRow(category)
                }
            }
            .disabled(!store.config.alertsEnabled)
        }
        .formStyle(.grouped)
        .task { store.notificationStatus = await NotificationsController.shared.authorizationDescription() }
        .sheet(item: $editingAlert) { alert in ActivityAlertEditor(alert: alert).environment(store) }
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
            Section("Dev tools included in Full Clean") {
                ForEach(ToolCleaner.tools) { tool in
                    Toggle(isOn: Binding(
                        get: { store.config.enabledDevTools.contains(tool.id) },
                        set: { enabled in
                            if enabled { store.config.enabledDevTools.insert(tool.id) }
                            else { store.config.enabledDevTools.remove(tool.id) }
                        }
                    )) {
                        HStack {
                            Text(tool.name)
                            Spacer()
                            if store.detectedTools[tool.id] == nil {
                                Text("Not installed").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(store.detectedTools[tool.id] == nil || store.isBusy)
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
                Text("A storage cleaner with automatic file rules and configurable storage and file-activity alerts. No third-party dependencies.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Safety") {
                Text("Cleanup uses a strict deletion allowlist. File Rules only manage explicitly selected folders and never replace existing files or permanently delete them. The administrator cleanup step shows its exact script before running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
