import Foundation

public enum AdminCleanerError: Error, LocalizedError {
    case cancelledOrFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelledOrFailed(let detail):
            return detail.isEmpty ? "The administrator step was cancelled." : detail
        }
    }
}

public enum AdminCleaner {
    /// Directories whose contents may be cleared with admin rights. The parent
    /// directory itself is kept.
    static let systemTargets = [
        "/Library/Caches",
        "/Library/Logs",
        "/Library/Application Support/CrashReporter",
    ]

    public static func systemCleanScript(includeSnapshots: Bool) async -> String {
        var lines = [
            "#!/bin/sh",
            "# MrMcLean system cleanup. Review every line before continuing.",
            "set -u",
            "status=0",
        ]
        for target in systemTargets {
            lines.append("if [ -d \"\(target)\" ]; then /usr/bin/find \"\(target)\" -mindepth 1 -maxdepth 1 -exec /bin/rm -rf {} + || status=1; fi")
        }
        lines.append("/usr/bin/find /private/var/log -type f -name '*.gz' -delete || status=1")
        if includeSnapshots {
            lines.append("# Time Machine local snapshots")
            for command in await SnapshotTool.deleteCommands() {
                lines.append(command + " || status=1")
            }
        }
        lines.append("exit $status")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func snapshotOnlyScript() async -> String {
        var lines = ["#!/bin/sh", "set -u", "status=0"]
        for command in await SnapshotTool.deleteCommands() { lines.append(command + " || status=1") }
        lines.append("exit $status")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write the script to a temp file and run it once via a single authenticated
    /// `osascript` call.
    public static func run(script: String) async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mrmclean-\(UUID().uuidString).sh")
        try script.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let appleScript = "do shell script \"/bin/sh \" & quoted form of \"\(fileURL.path)\" with administrator privileges"
        let result = await Shell.result("/usr/bin/osascript", ["-e", appleScript], timeout: 900)
        if !result.succeeded {
            throw AdminCleanerError.cancelledOrFailed(result.failureDescription ?? "The administrator step failed.")
        }
    }
}
