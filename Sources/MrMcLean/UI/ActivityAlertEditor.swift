import SwiftUI
import MrMcLeanCore

struct ActivityAlertEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var alert: ActivityAlertConfig
    @State private var folderError: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("App File Activity Alert").font(.title2.bold()).padding(20)
            Form {
                Section("Watch a folder") {
                    TextField("App or folder name", text: $alert.name)
                    FolderPickerRow(title: "Logs or output folder", path: $alert.folder)
                    Toggle("Include subfolders", isOn: $alert.includesSubfolders)
                    Text("Choose a specific app’s folder, such as ~/Library/Logs/ExampleApp. Every writer in this folder contributes to the alert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Alert when either threshold is reached") {
                    Picker("Within the last", selection: $alert.windowMinutes) {
                        Text("1 minute").tag(1.0)
                        Text("5 minutes").tag(5.0)
                        Text("15 minutes").tag(15.0)
                        Text("30 minutes").tag(30.0)
                        Text("1 hour").tag(60.0)
                    }
                    Toggle("Count new files", isOn: $alert.fileCountEnabled)
                    if alert.fileCountEnabled {
                        TextField("At least this many files", value: $alert.fileCountThreshold, format: .number)
                    }
                    Toggle("Measure added data", isOn: $alert.growthEnabled)
                    if alert.growthEnabled {
                        TextField("At least this many MB", value: $alert.growthMB, format: .number)
                    }
                    Text("Added data includes new files and growth of existing files, such as a single expanding log. Deletions do not cancel out growth. Repeats use the shared alert cooldown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Enable this alert", isOn: $alert.isEnabled)
                    if let error = alert.validationError ?? folderError { Text(error).foregroundStyle(.red).font(.callout) }
                }
            }.formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Alert", action: save).keyboardShortcut(.defaultAction)
                    .disabled(alert.validationError != nil)
            }.padding(16)
        }.frame(width: 560, height: 620)
    }

    private func save() {
        do {
            alert.folder = try ManagedFolder.resolve(alert.folder, readOnly: true).path
            if let index = store.config.activityAlerts.firstIndex(where: { $0.id == alert.id }) {
                if store.config.activityAlerts[index].monitoringConfig != alert.monitoringConfig { alert.lastAlertDate = nil }
                store.config.activityAlerts[index] = alert
            } else { store.config.activityAlerts.append(alert) }
            dismiss()
        } catch { folderError = error.localizedDescription }
    }
}
