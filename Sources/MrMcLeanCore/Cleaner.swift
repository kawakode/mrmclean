import Foundation

public struct CleanOutcome: Sendable {
    public var freedBytes: Int64
    public var removed: [String]
    public var failed: [String]
    public var trashedBytes: Int64

    public init(freedBytes: Int64 = 0, removed: [String] = [], failed: [String] = [], trashedBytes: Int64 = 0) {
        self.freedBytes = freedBytes
        self.removed = removed
        self.failed = failed
        self.trashedBytes = trashedBytes
    }
}

public enum Cleaner {
    public enum Mode: Sendable { case hardDelete, moveToTrash }

    public static func mode(for category: StorageCategory, hardDeleteNonCache: Bool) -> Mode {
        (category.hardByDefault || hardDeleteNonCache) ? .hardDelete : .moveToTrash
    }

    /// Validate then remove each item. Sizes are taken from the caller's scan so
    /// nothing is re-measured.
    public static func execute(items: [SizedEntry], mode: Mode) -> CleanOutcome {
        let fileManager = FileManager.default
        var outcome = CleanOutcome()
        for item in uniqueItems(items) {
            do {
                try SafePath.validate(item.path)
                guard fileManager.fileExists(atPath: item.path) else { continue }
                let url = URL(fileURLWithPath: item.path)
                switch mode {
                case .hardDelete:
                    try fileManager.removeItem(at: url)
                    outcome.freedBytes += max(0, item.bytes)
                case .moveToTrash:
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                    outcome.trashedBytes += max(0, item.bytes)
                }
                outcome.removed.append(item.path)
            } catch {
                outcome.failed.append(item.path)
            }
        }
        return outcome
    }

    /// A parent and its children can appear in overlapping scan categories.
    /// Count and remove that tree only once.
    public static func uniqueItems(_ items: [SizedEntry]) -> [SizedEntry] {
        var accepted: [SizedEntry] = []
        for item in items.sorted(by: { $0.path.count < $1.path.count }) {
            guard !accepted.contains(where: {
                item.path == $0.path || item.path.hasPrefix($0.path + "/")
            }) else { continue }
            accepted.append(item)
        }
        return accepted
    }
}
