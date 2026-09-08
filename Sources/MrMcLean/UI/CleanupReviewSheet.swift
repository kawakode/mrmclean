import SwiftUI
import MrMcLeanCore

struct CleanupRequest: Identifiable {
    let id = UUID()
    var title: String
    var items: [SizedEntry]
    var mode: Cleaner.Mode
    var toolIDs: [String] = []

    var bytes: Int64 { items.reduce(0) { $0 + max(0, $1.bytes) } }
}

struct CleanupReviewSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: CleanupRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title).font(.title3.weight(.semibold))
            Text(request.toolIDs.isEmpty
                 ? "\(request.items.count) items · \(Format.bytes(request.bytes))"
                 : "Review the selected tool commands before running them.")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if request.toolIDs.isEmpty {
                        ForEach(request.items) { entry in
                            HStack(alignment: .top) {
                                Text(entry.path).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Format.bytes(entry.bytes)).monospacedDigit().fixedSize()
                            }
                            Divider()
                        }
                    } else {
                        ForEach(ToolCleaner.tools.filter { request.toolIDs.contains($0.id) }) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.name).fontWeight(.medium)
                                Text(([store.detectedTools[tool.id] ?? tool.binary] + tool.cleanArguments)
                                    .joined(separator: " "))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            Divider()
                        }
                    }
                }
                .font(.callout)
                .padding(12)
            }
            .frame(height: 240)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            Text(warning)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.mode == .moveToTrash ? "Move to Trash" : "Clean") {
                    dismiss()
                    Task { await store.performCleanup(request) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canStartOperation)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var warning: String {
        if !request.toolIDs.isEmpty {
            return "These commands remove cached data and unused resources. Docker also removes stopped containers and unused images and networks. Close active development work first."
        }
        if request.mode == .moveToTrash {
            return "Items move to the Trash so you can restore them. Space is freed only after you empty the Trash."
        }
        return "These items will be permanently deleted. Close apps using them before continuing."
    }
}
