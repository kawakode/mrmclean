import Foundation

public struct LocalSnapshot: Sendable, Identifiable, Hashable {
    public var name: String
    public var date: Date?
    public var id: String { name }

    public var stamp: String? { SnapshotTool.stamp(from: name) }
}

public enum SnapshotTool {
    static let tmutil = "/usr/bin/tmutil"
    static let diskutil = "/usr/sbin/diskutil"

    /// `com.apple.TimeMachine.2024-01-15-123456.local` -> `2024-01-15-123456`
    public static func stamp(from snapshotName: String) -> String? {
        let prefix = "com.apple.TimeMachine."
        guard snapshotName.hasPrefix(prefix) else { return nil }
        var rest = snapshotName.dropFirst(prefix.count)
        if let dot = rest.firstIndex(of: ".") { rest = rest[..<dot] }
        let value = String(rest)
        return value.isEmpty ? nil : value
    }

    public static func date(from stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: stamp)
    }

    public static func list() async -> [LocalSnapshot] {
        let output = await Shell.run(tmutil, ["listlocalsnapshots", "/"], timeout: 30)
        return output.split(separator: "\n").compactMap { line -> LocalSnapshot? in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix("com.apple.TimeMachine.") else { return nil }
            let stamp = stamp(from: name)
            return LocalSnapshot(name: name, date: stamp.flatMap(date(from:)))
        }
    }

    /// Best-effort total size. Newer macOS reports a per-snapshot disk size in
    /// `diskutil apfs listSnapshots`; older releases do not, so this can be 0.
    public static func totalBytesBestEffort() async -> Int64 {
        let output = await Shell.run(diskutil, ["apfs", "listSnapshots", "/"], timeout: 30)
        var total: Int64 = 0
        for line in output.split(separator: "\n") where line.contains("Snapshot Disk Size") {
            guard
                let open = line.firstIndex(of: "("),
                let close = line.firstIndex(of: ")"),
                open < close
            else { continue }
            let inside = line[line.index(after: open)..<close]
            if let value = inside.split(separator: " ").first.flatMap({ Int64($0) }) {
                total += value
            }
        }
        return total
    }

    /// Shell lines that remove every current local snapshot. Run under admin.
    public static func deleteCommands() async -> [String] {
        await list().compactMap { snapshot in
            snapshot.stamp.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }
        }
    }
}
