import Foundation

public struct DiskInfo: Sendable, Equatable {
    public var totalBytes: Int64
    public var rawAvailable: Int64
    public var importantAvailable: Int64

    public init(totalBytes: Int64, rawAvailable: Int64, importantAvailable: Int64) {
        self.totalBytes = totalBytes
        self.rawAvailable = rawAvailable
        self.importantAvailable = importantAvailable
    }

    /// Free space the user can realistically expect, including purgeable content.
    public var availableBytes: Int64 {
        importantAvailable > 0 ? importantAvailable : rawAvailable
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    /// Space that macOS reports as free-if-needed but is currently held by caches
    /// and snapshots.
    public var purgeableBytes: Int64 { max(0, importantAvailable - rawAvailable) }

    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public static func current(path: String = "/") -> DiskInfo {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        return DiskInfo(
            totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
            rawAvailable: Int64(values?.volumeAvailableCapacity ?? 0),
            importantAvailable: values?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
