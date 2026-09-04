import Foundation

public enum Scanner {
    /// Scan every category. `onProgress` is called on the calling actor.
    public static func run(
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async -> ScanSnapshot {
        let categories = Catalog.all
        let disk = DiskInfo.current()
        var scans: [CategoryScan] = []

        await withTaskGroup(of: CategoryScan.self) { group in
            for category in categories {
                group.addTask { await measure(category) }
            }
            var done = 0
            for await scan in group {
                scans.append(scan)
                done += 1
                onProgress(Double(done) / Double(categories.count), scan.category.name)
            }
        }

        scans.sort { $0.totalBytes > $1.totalBytes }
        return ScanSnapshot(disk: disk, categories: scans, date: Date())
    }

    static func measure(_ category: StorageCategory) async -> CategoryScan {
        switch category.action {
        case .thinSnapshots:
            let snapshots = await SnapshotTool.list()
            let bytes = await SnapshotTool.totalBytesBestEffort()
            let entries = snapshots.map { SizedEntry(path: $0.name, bytes: 0) }
            return CategoryScan(category: category, totalBytes: bytes,
                                entries: entries, itemCount: snapshots.count)

        case .toolCleanup:
            var total: Int64 = 0
            var entries: [SizedEntry] = []
            let detected = ToolCleaner.detect()
            for tool in ToolCleaner.tools {
                guard detected[tool.id] != nil, let cache = tool.cacheDirectory else { continue }
                let path = expandTilde(cache)
                guard directoryExists(path) else { continue }
                let bytes = await SizeProbe.total(path)
                total += bytes
                entries.append(SizedEntry(path: path, bytes: bytes))
            }
            entries.sort { $0.bytes > $1.bytes }
            return CategoryScan(category: category, totalBytes: total,
                                entries: entries, itemCount: entries.count)

        case .reviewOnly where category.id == "largeFiles":
            // Deferred: run on explicit request only.
            return CategoryScan(category: category, totalBytes: 0, entries: [], itemCount: 0)

        default:
            var total: Int64 = 0
            var entries: [SizedEntry] = []
            for probe in category.probes {
                switch probe {
                case .breakdown(let directory):
                    let (subtotal, children) = await SizeProbe.breakdown(directory)
                    total += subtotal
                    entries.append(contentsOf: children)
                case .glob(let pattern):
                    for match in globMatches(pattern) {
                        let bytes = await SizeProbe.total(match)
                        total += bytes
                        if bytes > 0 { entries.append(SizedEntry(path: match, bytes: bytes)) }
                    }
                }
            }
            entries.sort { $0.bytes > $1.bytes }
            return CategoryScan(category: category, totalBytes: total,
                                entries: entries, itemCount: entries.count)
        }
    }
}
