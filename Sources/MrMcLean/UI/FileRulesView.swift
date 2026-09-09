import SwiftUI
import AppKit
import MrMcLeanCore

struct FolderPickerRow: View {
    var title: String
    @Binding var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.prompt = "Choose Folder"
                    if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: expandTilde(path)) }
                    if panel.runModal() == .OK, let url = panel.url { path = url.resolvingSymlinksInPath().path }
                }
            }
            Text(path.isEmpty ? "No folder selected" : path)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
        }
    }
}

struct FileRulesView: View {
    @Environment(Store.self) private var store
    @State private var editingRule: FileRule?
    @State private var preview: RulePreview?
    @State private var showPreview = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("File Rules").font(.largeTitle.bold())
                        Text("Organize files automatically in the folders you choose.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { editingRule = FileRule() } label: { Label("Add Rule", systemImage: "plus") }
                        .disabled(store.isBusy)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Run rules automatically while MrMcLean is open", isOn: $store.config.automationEnabled)
                            .disabled(store.ruleHistoryProblem != nil && !store.config.automationEnabled)
                        HStack {
                            Picker("Check folders every", selection: $store.config.ruleIntervalMinutes) {
                                Text("1 minute").tag(1.0)
                                Text("5 minutes").tag(5.0)
                                Text("15 minutes").tag(15.0)
                                Text("1 hour").tag(60.0)
                            }.frame(maxWidth: 300)
                            Spacer()
                            Button("Run Enabled Rules Now") { Task { await store.runRules() } }
                                .disabled(!store.canStartOperation || !store.config.automationEnabled
                                          || !store.config.fileRules.contains(where: \.isEnabled) || store.ruleHistoryProblem != nil)
                        }
                        Text(store.ruleRunSummary).font(.caption).foregroundStyle(.secondary)
                        if let problem = store.ruleHistoryProblem { Text(problem).font(.callout).foregroundStyle(.red) }
                    }
                }
                if store.config.fileRules.isEmpty {
                    ContentUnavailableView("Your folders, your rules", systemImage: "folder.badge.gearshape",
                        description: Text("Choose a folder, match files by metadata, and add actions. Preview the matches before enabling a rule."))
                        .padding(.vertical, 18)
                }
                ForEach(store.config.fileRules) { rule in
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Toggle(rule.name, isOn: Binding(
                                    get: { store.config.fileRules.first(where: { $0.id == rule.id })?.isEnabled ?? false },
                                    set: { value in
                                        if let index = store.config.fileRules.firstIndex(where: { $0.id == rule.id }) {
                                            store.config.fileRules[index].isEnabled = value
                                        }
                                    }))
                                    .font(.headline)
                                    .disabled(store.isBusy || rule.validationError != nil)
                                Spacer()
                                Button("Preview") {
                                    Task {
                                        preview = await store.previewRule(rule)
                                        showPreview = preview != nil
                                    }
                                }.disabled(!store.canStartOperation)
                                Button("Edit") { editingRule = rule }.disabled(store.isBusy)
                                Menu {
                                    Button("Move Up") { move(rule, offset: -1) }
                                        .disabled(store.config.fileRules.first?.id == rule.id)
                                    Button("Move Down") { move(rule, offset: 1) }
                                        .disabled(store.config.fileRules.last?.id == rule.id)
                                    Button("Delete Rule", role: .destructive) { store.config.fileRules.removeAll { $0.id == rule.id } }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).frame(width: 24).disabled(store.isBusy)
                            }
                            Text(rule.folder).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text("Match \(rule.matchMode.rawValue) of \(rule.conditions.count) condition(s) → \(rule.actions.map { $0.kind.title }.joined(separator: ", "))")
                                .font(.callout)
                            if let error = rule.validationError { Text(error).font(.caption).foregroundStyle(.red) }
                        }
                    }
                }
                Text("Rules run in order, handling a file at most once per pass and once per rule version. Editing conditions or actions permits another run. Files modified in the last 30 seconds, incomplete downloads, hidden files, links and packages are skipped. Trash actions keep files recoverable until the Trash is emptied.")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.recentRuleActivity.isEmpty {
                    Text("Recent Activity").font(.title3.bold())
                    ForEach(store.recentRuleActivity) { receipt in
                        Card {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: receipt.status == .completed ? "checkmark.circle" : "exclamationmark.triangle")
                                        .foregroundStyle(receipt.status == .completed ? Color.green : Color.orange)
                                    Text(receipt.ruleName).font(.headline)
                                    Spacer()
                                    Text(receipt.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(receipt.path).font(.caption).textSelection(.enabled)
                                Text(receipt.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if receipt.status != .completed {
                                    Text("\(receipt.status == .pending ? "Interrupted" : "Failed"): this file will not be retried automatically. Review it before changing the rule.")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }.padding(24)
        }
        .navigationTitle("File Rules")
        .sheet(item: $editingRule) { rule in
            FileRuleEditor(rule: rule).environment(store)
        }
        .sheet(isPresented: $showPreview) {
            if let preview { RulePreviewSheet(preview: preview) }
        }
    }

    private func move(_ rule: FileRule, offset: Int) {
        guard let index = store.config.fileRules.firstIndex(where: { $0.id == rule.id }) else { return }
        let target = index + offset
        guard store.config.fileRules.indices.contains(target) else { return }
        store.config.fileRules.swapAt(index, target)
    }
}

struct FileRuleEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var rule: FileRule
    @State private var folderError: String?
    @State private var preview: RulePreview?
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit File Rule").font(.title2.bold()).padding(20)
            Form {
                Section("Folder") {
                    TextField("Rule name", text: $rule.name)
                    FolderPickerRow(title: "Manage files in", path: $rule.folder)
                    Toggle("Include subfolders", isOn: $rule.includesSubfolders)
                }
                Section("Conditions") {
                    Picker("Match", selection: $rule.matchMode) {
                        Text("All conditions").tag(FileRule.MatchMode.all)
                        Text("Any condition").tag(FileRule.MatchMode.any)
                    }
                    ForEach($rule.conditions) { $condition in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("Metadata", selection: $condition.field) {
                                    ForEach(MetadataField.allCases, id: \.self) { field in Text(field.title).tag(field) }
                                }.labelsHidden()
                                Picker("Comparison", selection: $condition.comparison) {
                                    ForEach(MetadataComparison.choices(for: condition.field), id: \.self) { comparison in
                                        Text(comparison.title).tag(comparison)
                                    }
                                }.labelsHidden()
                                Button { rule.conditions.removeAll { $0.id == condition.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).help("Remove condition")
                            }
                            if condition.field == .kind {
                                Picker("Kind", selection: $condition.value) {
                                    ForEach(ManagedFileKind.allCases, id: \.self) { kind in Text(kind.rawValue.capitalized).tag(kind.rawValue) }
                                }
                            } else { TextField(condition.field.isNumber ? "Number" : "Text (case insensitive)", text: $condition.value) }
                        }
                        .onChange(of: condition.field) { _, field in
                            condition.comparison = MetadataComparison.choices(for: field)[0]
                            condition.value = field.isNumber ? "30" : field == .kind ? "document" : field == .fileExtension ? "pdf" : ""
                        }
                    }
                    Button("Add Condition") { rule.conditions.append(FileCondition()) }
                    Text("Size uses decimal MB. Dates are measured in days; last accessed uses filesystem access time. Files with no access date do not match that condition.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Actions, in order") {
                    ForEach($rule.actions) { $action in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("Action", selection: $action.kind) {
                                    ForEach(FileActionKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                                }
                                Button { rule.actions.removeAll { $0.id == action.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).help("Remove action")
                            }
                            switch action.kind {
                            case .move:
                                FolderPickerRow(title: "Destination", path: $action.value)
                                TextField("Subfolders (optional)", text: $action.subfolder, prompt: Text("{year}/{month}"))
                                Text("Source and destination must be on the same volume.").font(.caption).foregroundStyle(.secondary)
                            case .tag: TextField("Tag", text: $action.value)
                            case .rename: TextField("Full filename", text: $action.value, prompt: Text("{created}-{name}.{ext}"))
                            case .trash: Text("Matching files will move to the Trash automatically when enabled.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: action.kind) { _, kind in
                            action.value = kind == .rename ? "{created}-{name}.{ext}" : kind == .tag ? "Organized" : ""
                            action.subfolder = ""
                        }
                    }
                    Button("Add Action") { rule.actions.append(FileAction()) }
                    Text("Filename and subfolder placeholders: {name}, {ext}, {year}, {month}, {day}, {created}, {modified}. Dates use the file’s creation date unless {modified} is specified. Existing files are never replaced.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Enable this rule", isOn: $rule.isEnabled)
                    Text("Enabling allows automatic changes when the main File Rules switch is on. Preview first to check which files match. Saving changes to a rule’s behavior allows it to handle previously processed files again.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = rule.validationError ?? folderError { Text(error).foregroundStyle(.red).font(.callout) }
                }
            }.formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview") {
                    Task {
                        preview = await store.previewRule(rule)
                        showPreview = preview != nil
                    }
                }.disabled(rule.validationError != nil || !store.canStartOperation)
                Button("Save Rule", action: save).keyboardShortcut(.defaultAction)
                    .disabled(rule.validationError != nil || store.isBusy)
            }.padding(16)
        }
        .frame(width: 620, height: 720)
        .sheet(isPresented: $showPreview) { if let preview { RulePreviewSheet(preview: preview) } }
    }

    private func save() {
        do {
            rule.folder = try ManagedFolder.resolve(rule.folder).path
            for index in rule.actions.indices where rule.actions[index].kind == .move {
                rule.actions[index].value = try ManagedFolder.resolve(rule.actions[index].value).path
            }
            if let index = store.config.fileRules.firstIndex(where: { $0.id == rule.id }) {
                store.config.fileRules[index] = rule
            } else { store.config.fileRules.append(rule) }
            dismiss()
        } catch { folderError = error.localizedDescription }
    }
}

struct RulePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    var preview: RulePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview: \(preview.rule.name)").font(.title2.bold())
            Text("\(preview.actionableCount) file(s) ready · \(preview.alreadyHandled) already handled · \(preview.settling) still settling")
                .font(.callout).foregroundStyle(.secondary)
            Text("This preview makes no changes. Enabled rules use current metadata when they run.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(preview.issues, id: \.self) { issue in Text(issue).foregroundStyle(.red) }
                    if !preview.issues.isEmpty { Text("No actions will run while the folder scan is incomplete.").font(.callout) }
                    if preview.files.isEmpty && preview.issues.isEmpty { Text("No new files match this rule.").foregroundStyle(.secondary) }
                    ForEach(Array(preview.files.prefix(200))) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.file.url.path).font(.callout).textSelection(.enabled)
                            if let problem = item.problem { Text("Skipped: \(problem)").foregroundStyle(.orange).font(.caption) }
                            else if item.actions.isEmpty { Text("Already organized; no changes needed.").font(.caption).foregroundStyle(.secondary) }
                            else {
                                ForEach(Array(item.actions.enumerated()), id: \.offset) { _, action in
                                    Text(action.description).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                        Divider()
                    }
                    if preview.files.count > 200 { Text("Showing the first 200 of \(preview.files.count) matches. Counts include all matches.").font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 640, height: 520)
    }
}
