import Foundation

public enum LargeFiles {
    /// Files larger than `minimumBytes` inside the home folder. Runs `find`, which
    /// may prompt for access to protected folders the first time.
    public static func scan(minimumBytes: Int64 = 1_073_741_824, limit: Int = 100) async -> [SizedEntry] {
        let output = await Shell.run(
            "/usr/bin/find",
            [userHome, "-type", "f", "-size", "+\(minimumBytes)c",
             "-not", "-path", "*/.Trash/*"],
            timeout: 240
        )
        var entries: [SizedEntry] = []
        for line in output.split(separator: "\n") {
            let path = String(line)
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                let size = (attributes[.size] as? NSNumber)?.int64Value
            else { continue }
            entries.append(SizedEntry(path: path, bytes: size))
        }
        return Array(entries.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}
