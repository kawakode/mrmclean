import Foundation

public struct CleanOutcome: Sendable {
    public var freedBytes: Int64
    public var removed: [String]
    public var failed: [String]

    public init(freedBytes: Int64 = 0, removed: [String] = [], failed: [String] = []) {
        self.freedBytes = freedBytes
        self.removed = removed
        self.failed = failed
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
        for item in items {
            do {
                try SafePath.validate(item.path)
                guard fileManager.fileExists(atPath: item.path) else { continue }
                let url = URL(fileURLWithPath: item.path)
                switch mode {
                case .hardDelete:
                    try fileManager.removeItem(at: url)
                case .moveToTrash:
                    try fileManager.trashItem(at: url, resultingItemURL: nil)
                }
                outcome.freedBytes += item.bytes
                outcome.removed.append(item.path)
            } catch {
                outcome.failed.append(item.path)
            }
        }
        return outcome
    }
}
