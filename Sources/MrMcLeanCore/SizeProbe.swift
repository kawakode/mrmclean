import Foundation

/// Parsing helpers for `du` output, kept separate so they can be tested without
/// spawning a process.
public enum DuParse {
    /// Each line of `du` output is `<kilobytes>\t<path>`.
    public static func lines(_ output: String) -> [(path: String, kilobytes: Int64)] {
        output.split(separator: "\n").compactMap { line in
            guard let tab = line.firstIndex(of: "\t") else { return nil }
            let sizeField = line[..<tab].trimmingCharacters(in: .whitespaces)
            guard let kilobytes = Int64(sizeField) else { return nil }
            let path = String(line[line.index(after: tab)...])
            return (path, kilobytes)
        }
    }

    /// Split `du -d 1` output into the total for `root` and its immediate children.
    public static func breakdown(_ output: String, root: String)
        -> (total: Int64, children: [SizedEntry]) {
        var total: Int64 = 0
        var children: [SizedEntry] = []
        for line in lines(output) {
            let bytes = line.kilobytes * 1024
            if line.path == root || line.path == root + "/" {
                total = bytes
            } else {
                children.append(SizedEntry(path: line.path, bytes: bytes))
            }
        }
        if total == 0 { total = children.reduce(0) { $0 + $1.bytes } }
        children.sort { $0.bytes > $1.bytes }
        return (total, children)
    }
}

/// What kept a size probe from returning a complete figure. An empty set means
/// the measurement is trustworthy.
public struct ProbeIssues: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `du` could not enter a folder (missing Full Disk Access, or a root-owned
    /// path). The reported size is lower than the real usage.
    public static let permissionDenied = ProbeIssues(rawValue: 1 << 0)
    /// `du` was killed before it finished walking the tree.
    public static let timedOut = ProbeIssues(rawValue: 1 << 1)

    /// Classify a `du` run from its stderr and whether the child was killed.
    public static func classify(stderr: String, timedOut: Bool) -> ProbeIssues {
        var issues: ProbeIssues = []
        if timedOut { issues.insert(.timedOut) }
        if stderr.contains("Operation not permitted") || stderr.contains("Permission denied") {
            issues.insert(.permissionDenied)
        }
        return issues
    }
}

enum SizeProbe {
    static let du = "/usr/bin/du"

    /// `du -d 1` on a directory: returns its total, its immediate children, and
    /// anything that stopped the walk from completing.
    static func breakdown(_ directory: String, timeout: TimeInterval = 120) async
        -> (total: Int64, children: [SizedEntry], issues: ProbeIssues) {
        let path = expandTilde(directory)
        guard directoryExists(path) else { return (0, [], []) }
        let result = await Shell.result(du, ["-k", "-x", "-d", "1", path], timeout: timeout)
        let parsed = DuParse.breakdown(result.stdout, root: path)
        return (parsed.total, parsed.children,
                ProbeIssues.classify(stderr: result.stderr, timedOut: result.timedOut))
    }

    /// `du -s` on a single path: total only, plus anything that stopped the walk.
    static func total(_ path: String, timeout: TimeInterval = 90) async
        -> (bytes: Int64, issues: ProbeIssues) {
        let expanded = expandTilde(path)
        guard FileManager.default.fileExists(atPath: expanded) else { return (0, []) }
        let result = await Shell.result(du, ["-s", "-k", "-x", expanded], timeout: timeout)
        let bytes = DuParse.lines(result.stdout).first.map { $0.kilobytes * 1024 } ?? 0
        return (bytes, ProbeIssues.classify(stderr: result.stderr, timedOut: result.timedOut))
    }
}
