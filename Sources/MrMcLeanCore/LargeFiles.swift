import Foundation

public struct LargeFileScan: Sendable {
    public var entries: [SizedEntry]
    public var issues: ProbeIssues
    public var failure: String?
    public var totalBytes: Int64
    public var totalFound: Int
    public var date: Date

    public var isPartial: Bool { !issues.isEmpty || failure != nil }
}

public enum LargeFiles {
    /// Null-delimited paths preserve filenames containing newlines. Keep partial
    /// results and their errors so inaccessible folders never look like an empty disk.
    public static func scan(minimumBytes: Int64 = 1_073_741_824, limit: Int = 100,
                            root: String = userHome) async -> LargeFileScan {
        let output = await Shell.result(
            "/usr/bin/find",
            [root, "-name", ".Trash", "-type", "d", "-prune", "-o",
             "-type", "f", "-size", "+\(max(0, minimumBytes))c", "-print0"],
            timeout: 240
        )
        var entries: [SizedEntry] = []
        for path in output.stdout.split(separator: "\0").map(String.init) {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let size = (attributes[.size] as? NSNumber)?.int64Value
            else { continue }
            entries.append(SizedEntry(path: path, bytes: size))
        }
        entries.sort { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }
        let issues = ProbeIssues.classify(stderr: output.stderr, timedOut: output.timedOut)
        return LargeFileScan(entries: Array(entries.prefix(max(0, limit))), issues: issues,
                             failure: output.failureDescription, totalBytes: entries.reduce(0) { $0 + $1.bytes },
                             totalFound: entries.count, date: Date())
    }
}
