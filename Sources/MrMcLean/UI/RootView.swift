import SwiftUI
import MrMcLeanCore

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var selection: String? = "overview"
    @State private var showFullCleanSetup = false
    @State private var bannerDetails: Store.Banner?

    var body: some View {
        ZStack {
            mainInterface
                .disabled(store.showAccessGate || store.fullCleanReport != nil)

            if store.showAccessGate {
                FullDiskAccessGate()
                    .transition(.opacity)
                    .zIndex(2)
            }

            if store.fullCleanReport != nil {
                FullCleanView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .animation(.smooth(duration: 0.35), value: store.showAccessGate)
        .animation(.smooth(duration: 0.35), value: store.fullCleanReport == nil)
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            openWindow(id: "main")
        }
        .onChange(of: store.pendingFullCleanRequest, initial: true) { _, pending in
            if pending {
                store.pendingFullCleanRequest = false
                if store.canStartOperation { showFullCleanSetup = true }
            }
        }
        .onChange(of: store.showAccessGate) { _, visible in
            if !visible { Task { await store.scan() } }
        }
        .sheet(item: Binding(get: { store.cleanupRequest }, set: { store.cleanupRequest = $0 })) { request in
            CleanupReviewSheet(request: request).environment(store)
        }
        .sheet(item: $bannerDetails) { banner in
            VStack(alignment: .leading, spacing: 16) {
                Text("Cleanup details").font(.headline)
                ScrollView {
                    Text(banner.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 280)
                HStack {
                    Spacer()
                    Button("Done") { bannerDetails = nil }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 520)
        }
        .sheet(isPresented: $showFullCleanSetup) {
            FullCleanSetupSheet()
                .environment(store)
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: "overview") {
                    Label("Overview", systemImage: "chart.pie")
                }
                NavigationLink(value: "fileRules") {
                    Label("File Rules", systemImage: "folder.badge.gearshape")
                }
                Section("Storage") {
                    ForEach(Catalog.all) { category in
                        NavigationLink(value: category.id) {
                            sidebarRow(category)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 232, ideal: 248, max: 300)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            detail
                .toolbar { toolbar }
        }
        .overlay(alignment: .bottom) { bannerView }
    }

    @ViewBuilder
    private func sidebarRow(_ category: StorageCategory) -> some View {
        HStack {
            Label(category.name, systemImage: category.symbol)
                .lineLimit(1).truncationMode(.tail)
                .help(category.name)
            Spacer()
            if let scan = store.snapshot?.category(category.id), scan.totalBytes > 0 {
                Text(Format.bytes(scan.totalBytes))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case "fileRules":
            FileRulesView()
        case .some(let id) where id != "overview":
            if let category = Catalog.category(id) {
                CategoryDetailView(category: category).id(category.id)
            } else {
                OverviewView(selection: $selection)
            }
        default:
            OverviewView(selection: $selection)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.scan() }
            } label: {
                Label(store.scanning ? "Scanning" : "Scan",
                      systemImage: store.scanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .disabled(!store.canStartOperation)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showFullCleanSetup = true
            } label: {
                Label("Full Clean", systemImage: "sparkles")
            }
            .disabled(!store.canStartOperation || store.snapshot == nil)
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 4) {
            if store.scanning {
                ProgressView(value: store.progress).progressViewStyle(.linear)
                Text(store.statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if store.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(store.statusText).font(.caption2).lineLimit(1)
                }
            } else if let date = store.snapshot?.date {
                Text("Scanned \(Format.relativeDate(date))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner = store.banner {
            HStack(alignment: .top, spacing: 10) {
                Text(banner.text).lineLimit(3)
                if banner.kind == .failure {
                    Button("Details") { bannerDetails = banner }
                        .buttonStyle(.plain)
                        .underline()
                }
                Button { store.banner = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Dismiss message")
            }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color(for: banner.kind), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .frame(maxWidth: 580)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner.id) {
                    guard banner.kind != .failure else { return }
                    do { try await Task.sleep(for: .seconds(7)) } catch { return }
                    if store.banner?.id == banner.id { store.banner = nil }
                }
        }
    }

    private func color(for kind: Store.Banner.Kind) -> Color {
        switch kind {
        case .info: return .secondary
        case .success: return .green
        case .failure: return .red
        }
    }
}
