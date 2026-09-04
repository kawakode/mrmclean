import SwiftUI
import MrMcLeanCore

struct CategoryDetailView: View {
    @Environment(Store.self) private var store
    let category: StorageCategory

    @State private var selectedPaths: Set<String> = []
    @State private var showScript = false
    @State private var scriptText = ""
    @State private var includeSnapshots = true
    @State private var working = false

    private var scan: CategoryScan? { store.snapshot?.category(category.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(20)
        }
        .navigationTitle(category.name)
        .sheet(isPresented: $showScript) { scriptSheet }
        .task(id: scan?.entries.map(\.path) ?? []) {
            let paths = Set(scan?.entries.map(\.path) ?? [])
            selectedPaths = selectedPaths.isEmpty ? paths : selectedPaths.intersection(paths)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch category.action {
        case .adminDelete: adminSection
        case .thinSnapshots: snapshotSection
        case .toolCleanup: toolSection
        case .reviewOnly where category.id == "largeFiles": largeFilesSection
        case .reviewOnly: reviewSection
        default: entriesSection
        }
    }

    // MARK: Header

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label(category.name, systemImage: category.symbol)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if let scan {
                        Text(category.id == "snapshots"
                             ? "\(scan.itemCount) snapshots"
                             : Format.bytes(scan.totalBytes))
                        .font(.title3).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text(category.blurb)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Entries

    private var entriesSection: some View {
        let entries = scan?.entries ?? []
        let mode = Cleaner.mode(for: category, hardDeleteNonCache: store.config.hardDeleteNonCache)
        return Card {
            if entries.isEmpty {
                Text("Nothing to clean here.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button(selectedPaths.count == entries.count ? "Deselect All" : "Select All") {
                            selectedPaths = selectedPaths.count == entries.count
                                ? [] : Set(entries.map(\.path))
                        }
                        .buttonStyle(.link)
                        Spacer()
                        Text("\(selectedPaths.count) selected, \(Format.bytes(selectedBytes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    Divider()
                    ForEach(entries) { entry in
                        Toggle(isOn: toggleBinding(for: entry.path)) {
                            HStack {
                                Text(entry.displayName).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.bytes(entry.bytes))
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 4)
                        Divider()
                    }
                    HStack {
                        Text(mode == .hardDelete
                             ? "Selected items are deleted permanently."
                             : "Selected items are moved to the Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clean Selected") {
                            Task { await runClean(entries) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedPaths.isEmpty || working || store.scanning)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: Review

    private var reviewSection: some View {
        let entries = scan?.entries ?? []
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review only. Open an item in Finder to remove it yourself.")
                    .font(.callout).foregroundStyle(.secondary)
                if entries.isEmpty {
                    Text("None found.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        revealRow(name: entry.displayName, bytes: entry.bytes, path: entry.path)
                    }
                }
            }
        }
    }

    private var largeFilesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Files over 1 GB in your home folder.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.scanningLargeFiles ? "Scanning..." : "Scan Now") {
                        Task { await store.scanLargeFiles() }
                    }
                    .disabled(store.scanningLargeFiles)
                }
                if store.largeFiles.isEmpty && !store.scanningLargeFiles {
                    Text("No results yet.").foregroundStyle(.secondary)
                }
                ForEach(store.largeFiles) { entry in
                    revealRow(
                        name: entry.path.replacingOccurrences(of: userHome, with: "~"),
                        bytes: entry.bytes,
                        path: entry.path
                    )
                }
            }
        }
    }

    private func revealRow(name: String, bytes: Int64, path: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(name).lineLimit(1).truncationMode(.middle).font(.callout)
                Spacer()
                Text(Format.bytes(bytes)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .buttonStyle(.link)
            }
            Divider()
        }
    }

    // MARK: Admin

    private var adminSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let scan {
                    Text("Around \(Format.bytes(scan.totalBytes)) in root-owned caches and logs.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("This runs one shell script with administrator rights. You see the exact commands first.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Also thin Time Machine local snapshots", isOn: $includeSnapshots)
                Button("Review Commands") {
                    Task {
                        scriptText = await AdminCleaner.systemCleanScript(includeSnapshots: includeSnapshots)
                        showScript = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
            }
        }
    }

    private var snapshotSection: some View {
        let entries = scan?.entries ?? []
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                if entries.isEmpty {
                    Text("No local snapshots.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(spacing: 6) {
                            HStack {
                                Text(entry.displayName).font(.callout)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                            }
                            Divider()
                        }
                    }
                    Text("Thinning removes every local snapshot. Time Machine creates new ones on its normal schedule. Needs administrator rights.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Thin Snapshots") {
                        Task {
                            scriptText = await AdminCleaner.snapshotOnlyScript()
                            showScript = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                }
            }
        }
    }

    // MARK: Dev tools

    private var toolSection: some View {
        let available = ToolCleaner.tools.filter { store.detectedTools[$0.id] != nil }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                if available.isEmpty {
                    Text("No supported dev tools found on this machine.").foregroundStyle(.secondary)
                } else {
                    ForEach(available) { tool in
                        Toggle(isOn: devToolBinding(for: tool.id)) {
                            HStack {
                                Text(tool.name)
                                Spacer()
                                if let bytes = toolCacheBytes(tool) {
                                    Text(Format.bytes(bytes))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button("Run Selected Cleanups") {
                        Task { await store.runDevTools(Array(store.config.enabledDevTools)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.config.enabledDevTools.isEmpty || store.scanning)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func toolCacheBytes(_ tool: DevTool) -> Int64? {
        guard let directory = tool.cacheDirectory else { return nil }
        let expanded = expandTilde(directory)
        return scan?.entries.first { $0.path == expanded }?.bytes
    }

    // MARK: Script sheet

    private var scriptSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commands to run").font(.headline)
            ScrollView {
                Text(scriptText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Cancel") { showScript = false }
                Button("Run with Administrator") {
                    showScript = false
                    Task {
                        working = true
                        await store.runAdminClean(script: scriptText)
                        working = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 520)
    }

    // MARK: Helpers

    private var selectedBytes: Int64 {
        (scan?.entries ?? [])
            .filter { selectedPaths.contains($0.path) }
            .reduce(0) { $0 + $1.bytes }
    }

    private func toggleBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { isOn in
                if isOn { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
            }
        )
    }

    private func devToolBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.config.enabledDevTools.contains(id) },
            set: { isOn in
                if isOn { store.config.enabledDevTools.insert(id) }
                else { store.config.enabledDevTools.remove(id) }
            }
        )
    }

    private func runClean(_ entries: [SizedEntry]) async {
        working = true
        let items = entries.filter { selectedPaths.contains($0.path) }
        await store.clean(categoryID: category.id, items: items)
        working = false
    }
}
