import SwiftUI
import MrMcLeanCore

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var selection: String? = "overview"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: "overview") {
                    Label("Overview", systemImage: "chart.pie")
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
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            openWindow(id: "main")
        }
        .overlay(alignment: .bottom) { bannerView }
    }

    @ViewBuilder
    private func sidebarRow(_ category: StorageCategory) -> some View {
        HStack {
            Label(category.name, systemImage: category.symbol)
            Spacer()
            if let scan = store.snapshot?.category(category.id), scan.totalBytes > 0 {
                Text(Format.bytes(scan.totalBytes))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .some(let id) where id != "overview":
            if let category = Catalog.category(id) {
                CategoryDetailView(category: category)
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
            .disabled(store.scanning)
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 4) {
            if store.scanning {
                ProgressView(value: store.progress).progressViewStyle(.linear)
                Text(store.statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
            Text(banner.text)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color(for: banner.kind), in: Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(4))
                    store.banner = nil
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
