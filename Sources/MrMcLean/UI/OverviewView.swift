import SwiftUI
import MrMcLeanCore

struct OverviewView: View {
    @Environment(Store.self) private var store
    @Binding var selection: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let snapshot = store.snapshot {
                    if snapshot.sizesUnderReported {
                        accessWarningCard(snapshot)
                    }
                    diskCard(snapshot)
                    fullCleanCard(snapshot)
                    categoriesCard(snapshot)
                    systemDataCard
                } else {
                    ContentUnavailableView(
                        "No scan yet",
                        systemImage: "externaldrive",
                        description: Text("Run a scan to see how your disk is used.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(20)
        }
        .navigationTitle("Overview")
    }

    private func diskCard(_ snapshot: ScanSnapshot) -> some View {
        let disk = snapshot.disk
        let used = disk.usedFraction
        let quick = disk.totalBytes > 0
            ? Double(snapshot.quickCleanBytes) / Double(disk.totalBytes) : 0
        return Card {
            HStack(spacing: 24) {
                ZStack {
                    RingChart(segments: [
                        RingSegment(value: max(0, used - quick), color: .accentColor),
                        RingSegment(value: quick, color: .orange),
                    ])
                    .frame(width: 150, height: 150)
                    VStack(spacing: 2) {
                        Text(Format.percent(used))
                            .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        Text("used").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    stat("Capacity", Format.bytes(disk.totalBytes))
                    stat("Available", Format.bytes(disk.availableBytes))
                    stat("Reclaimable now", Format.bytes(snapshot.quickCleanBytes), tint: .orange)
                    if disk.purgeableBytes > 0 {
                        stat("Purgeable", Format.bytes(disk.purgeableBytes))
                    }
                }
                Spacer()
            }
        }
    }

    private func fullCleanCard(_ snapshot: ScanSnapshot) -> some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Clean").font(.headline)
                    Text("Caches, logs, developer files and the Trash in one animated pass, with a report at the end.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Full Clean…") { store.requestFullClean() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.scanning || store.fullCleanReport != nil)
            }
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 24)
            Text(value).foregroundStyle(tint).monospacedDigit()
        }
        .font(.callout)
        .frame(maxWidth: 280, alignment: .leading)
    }

    private func categoriesCard(_ snapshot: ScanSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Categories").font(.headline)
                    Spacer()
                    Button("Clean Safe Caches") {
                        Task { await store.quickClean() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(snapshot.quickCleanBytes == 0 || store.scanning)
                }
                ForEach(snapshot.categories.filter { $0.totalBytes > 0 || $0.itemCount > 0 }) { scan in
                    categoryRow(scan, disk: snapshot.disk)
                }
            }
        }
    }

    private func categoryRow(_ scan: CategoryScan, disk: DiskInfo) -> some View {
        let fraction = disk.totalBytes > 0 ? Double(scan.totalBytes) / Double(disk.totalBytes) : 0
        let categoryConfig = store.config.category(scan.id)
        let threshold: Double? = categoryConfig.alertEnabled ? categoryConfig.thresholdPercent / 100 : nil
        let over = threshold.map { fraction >= $0 } ?? false
        return Button {
            selection = scan.id
        } label: {
            VStack(spacing: 6) {
                HStack {
                    Label(scan.category.name, systemImage: scan.category.symbol)
                    Spacer()
                    if scan.category.id == "snapshots" {
                        Text("\(scan.itemCount) snapshots").foregroundStyle(.secondary)
                    } else {
                        Text(Format.bytes(scan.totalBytes)).monospacedDigit()
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .font(.callout)
                UsageBar(fraction: fraction, threshold: threshold, tint: over ? .red : .accentColor)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func accessWarningCard(_ snapshot: ScanSnapshot) -> some View {
        let denied = snapshot.fullDiskAccess == .denied
        let issues = snapshot.scanIssues
        let canGrant = denied || issues.contains(.permissionDenied)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(denied ? "Full Disk Access is off" : "Some folders were skipped",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(accessWarningText(denied: denied, issues: issues))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if canGrant {
                        Button("Open Full Disk Access Settings") {
                            if let url = URL(string: FullDiskAccess.settingsURLString) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Rescan") { Task { await store.scan() } }
                        .disabled(store.scanning)
                }
            }
        }
    }

    private func accessWarningText(denied: Bool, issues: ProbeIssues) -> String {
        var parts: [String] = []
        if denied {
            parts.append("""
            MrMcLean can't read protected folders such as Mail, Messages, Safari and \
            the system caches, so the sizes below are lower than the real usage. Grant \
            Full Disk Access, then rescan.
            """)
        } else if issues.contains(.permissionDenied) {
            parts.append("""
            Some folders could not be read and were left out of the totals. Granting \
            Full Disk Access and rescanning gives an accurate picture.
            """)
        }
        if issues.contains(.timedOut) {
            parts.append("""
            A folder was too large to finish measuring in the time allowed, so its \
            category may read low. Rescan to try again.
            """)
        }
        return parts.joined(separator: " ")
    }

    private var systemDataCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("About System Data", systemImage: "info.circle").font(.headline)
                Text("""
                The large "System Data" figure in System Settings is mostly APFS snapshots, \
                virtual memory swap, and protected system files. MrMcLean clears the parts that \
                are safe to remove: snapshots, caches, logs, and diagnostic reports. The rest is \
                managed by macOS and freed automatically when the disk fills, or after a restart.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
