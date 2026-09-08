import Foundation

public struct SizedEntry: Sendable, Identifiable, Hashable {
    public var path: String
    public var bytes: Int64
    public var id: String { path }

    public init(path: String, bytes: Int64) {
        self.path = path
        self.bytes = bytes
    }

    public var displayName: String {
        (path as NSString).lastPathComponent
    }
}

public struct CategoryScan: Sendable, Identifiable {
    public var category: StorageCategory
    public var totalBytes: Int64
    public var entries: [SizedEntry]
    public var itemCount: Int
    /// Why `totalBytes` may be low. Empty when the measurement is complete.
    public var issues: ProbeIssues
    public var id: String { category.id }

    public init(category: StorageCategory, totalBytes: Int64, entries: [SizedEntry],
                itemCount: Int, issues: ProbeIssues = []) {
        self.category = category
        self.totalBytes = totalBytes
        self.entries = entries
        self.itemCount = itemCount
        self.issues = issues
    }
}

public struct ScanSnapshot: Sendable {
    public var disk: DiskInfo
    public var categories: [CategoryScan]
    public var date: Date
    /// Full Disk Access state at the time of the scan.
    public var fullDiskAccess: FullDiskAccessStatus

    public init(disk: DiskInfo, categories: [CategoryScan], date: Date,
                fullDiskAccess: FullDiskAccessStatus = .unknown) {
        self.disk = disk
        self.categories = categories
        self.date = date
        self.fullDiskAccess = fullDiskAccess
    }

    public mutating func recordLargeFiles(_ result: LargeFileScan) {
        let scan = CategoryScan(category: Catalog.largeFiles, totalBytes: result.totalBytes,
                                entries: result.entries, itemCount: result.totalFound, issues: result.issues)
        categories.removeAll { $0.id == "largeFiles" }
        categories.append(scan)
        categories.sort { $0.totalBytes > $1.totalBytes }
    }

    public func category(_ id: String) -> CategoryScan? {
        categories.first { $0.id == id }
    }

    /// The union of probe issues from categories the user is expected to be able
    /// to measure without elevation. Categories that clean root-owned paths
    /// (`adminDelete`) are excluded: `du` can't read those in full by design, and
    /// Full Disk Access doesn't change that.
    public var scanIssues: ProbeIssues {
        categories
            .filter { $0.category.action != .adminDelete }
            .reduce(into: ProbeIssues()) { $0.formUnion($1.issues) }
    }

    /// True when the reported category sizes are known to be lower than reality:
    /// a protected folder was skipped, a `du` pass timed out, or Full Disk Access
    /// is off.
    public var sizesUnderReported: Bool {
        !scanIssues.isEmpty || fullDiskAccess == .denied
    }

    /// The quick action only clears rebuildable caches and logs. Full Clean
    /// separately reviews developer archives and the Trash.
    public var quickCleanEntries: [SizedEntry] {
        Cleaner.uniqueItems(categories
            .filter { ["userCaches", "appLogs"].contains($0.id) }
            .flatMap(\.entries))
    }

    public var quickCleanBytes: Int64 {
        quickCleanEntries.reduce(0) { $0 + max(0, $1.bytes) }
    }
}
