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

enum SizeProbe {
    static let du = "/usr/bin/du"

    /// `du -d 1` on a directory: returns its total and its immediate children.
    static func breakdown(_ directory: String, timeout: TimeInterval = 120) async
        -> (total: Int64, children: [SizedEntry]) {
        let path = expandTilde(directory)
        guard directoryExists(path) else { return (0, []) }
        let output = await Shell.run(du, ["-k", "-x", "-d", "1", path], timeout: timeout)
        return DuParse.breakdown(output, root: path)
    }

    /// `du -s` on a single path: total only.
    static func total(_ path: String, timeout: TimeInterval = 90) async -> Int64 {
        let expanded = expandTilde(path)
        guard FileManager.default.fileExists(atPath: expanded) else { return 0 }
        let output = await Shell.run(du, ["-s", "-k", "-x", expanded], timeout: timeout)
        return DuParse.lines(output).first.map { $0.kilobytes * 1024 } ?? 0
    }
}
