import SwiftUI
import MrMcLeanCore

struct MenuBarView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = store.snapshot {
                HStack(spacing: 12) {
                    ZStack {
                        RingChart(
                            segments: [RingSegment(value: snapshot.disk.usedFraction, color: .accentColor)],
                            lineWidth: 7
                        )
                        .frame(width: 42, height: 42)
                        Text(Format.percent(snapshot.disk.usedFraction))
                            .font(.system(size: 10)).monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Format.bytes(snapshot.disk.availableBytes)) free")
                            .font(.callout.weight(.medium))
                        Text("of \(Format.bytes(snapshot.disk.totalBytes))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(snapshot.categories.filter { $0.totalBytes > 0 }.prefix(4)) { scan in
                    HStack {
                        Text(scan.category.name).font(.callout)
                        Spacer()
                        Text(Format.bytes(scan.totalBytes))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if snapshot.sizesUnderReported {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(snapshot.fullDiskAccess == .denied
                             ? "Full Disk Access off — sizes are low"
                             : "Some folders skipped — sizes are low")
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } else {
                Text("No scan yet").font(.callout).foregroundStyle(.secondary)
            }

            if store.scanning {
                ProgressView(value: store.progress).progressViewStyle(.linear)
            }

            Divider()
            HStack {
                Button(store.scanning ? "Scanning..." : "Scan Now") {
                    Task { await store.scan() }
                }
                .disabled(store.scanning)
                Spacer()
                Button("Clean Caches") {
                    Task { await store.quickClean() }
                }
                .disabled(store.scanning || (store.snapshot?.quickCleanBytes ?? 0) == 0)
            }
            Button {
                openWindow(id: "main")
                MainWindow.show()
                store.requestFullClean()
            } label: {
                Label("Full Clean…", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.scanning || store.fullCleanReport != nil)
            HStack {
                Button("Open") {
                    openWindow(id: "main")
                    MainWindow.show()
                }
                Spacer()
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") {
                    AppDelegate.userWantsQuit = true
                    NSApp.terminate(nil)
                }
            }
            .font(.callout)
        }
        .padding(12)
        .frame(width: 288)
    }
}
