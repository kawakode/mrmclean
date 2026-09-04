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
    public var id: String { category.id }

    public init(category: StorageCategory, totalBytes: Int64, entries: [SizedEntry], itemCount: Int) {
        self.category = category
        self.totalBytes = totalBytes
        self.entries = entries
        self.itemCount = itemCount
    }
}

public struct ScanSnapshot: Sendable {
    public var disk: DiskInfo
    public var categories: [CategoryScan]
    public var date: Date

    public init(disk: DiskInfo, categories: [CategoryScan], date: Date) {
        self.disk = disk
        self.categories = categories
        self.date = date
    }

    public func category(_ id: String) -> CategoryScan? {
        categories.first { $0.id == id }
    }

    /// Total that a plain "clean everything safe" pass would reclaim without a password.
    public var quickCleanBytes: Int64 {
        categories
            .filter { ["userCaches", "appLogs", "trash", "developer"].contains($0.id) }
            .reduce(0) { $0 + $1.totalBytes }
    }
}
