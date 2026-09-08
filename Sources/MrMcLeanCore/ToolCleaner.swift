import Foundation

public struct DevTool: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let binary: String
    public let cleanArguments: [String]
    /// Directory used to estimate reclaimable size, `~` allowed. May be nil.
    public let cacheDirectory: String?
}

public enum ToolCleaner {
    public static let tools: [DevTool] = [
        DevTool(id: "brew", name: "Homebrew", binary: "brew",
                cleanArguments: ["cleanup", "--prune=all", "-s"],
                cacheDirectory: "~/Library/Caches/Homebrew"),
        DevTool(id: "npm", name: "npm", binary: "npm",
                cleanArguments: ["cache", "clean", "--force"],
                cacheDirectory: "~/.npm/_cacache"),
        DevTool(id: "pnpm", name: "pnpm", binary: "pnpm",
                cleanArguments: ["store", "prune"],
                cacheDirectory: "~/Library/pnpm/store"),
        DevTool(id: "yarn", name: "Yarn", binary: "yarn",
                cleanArguments: ["cache", "clean"],
                cacheDirectory: "~/Library/Caches/Yarn"),
        DevTool(id: "pip", name: "pip", binary: "pip3",
                cleanArguments: ["cache", "purge"],
                cacheDirectory: "~/Library/Caches/pip"),
        DevTool(id: "pod", name: "CocoaPods", binary: "pod",
                cleanArguments: ["cache", "clean", "--all"],
                cacheDirectory: "~/Library/Caches/CocoaPods"),
        DevTool(id: "go", name: "Go module cache", binary: "go",
                cleanArguments: ["clean", "-modcache"],
                cacheDirectory: "~/go/pkg/mod"),
        DevTool(id: "xcodesim", name: "Xcode simulators", binary: "xcrun",
                cleanArguments: ["simctl", "delete", "unavailable"],
                cacheDirectory: nil),
        DevTool(id: "docker", name: "Docker", binary: "docker",
                cleanArguments: ["system", "prune", "-f"],
                cacheDirectory: nil),
    ]

    static let searchDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        "\(userHome)/.cargo/bin", "/usr/local/go/bin", "\(userHome)/go/bin",
    ]

    public static func resolve(_ binary: String) -> String? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = searchDirectories + envPath.split(separator: ":").map(String.init)
        for directory in directories {
            let candidate = directory + "/" + binary
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Map of tool id to resolved binary path, only for tools present on this machine.
    public static func detect() -> [String: String] {
        var found: [String: String] = [:]
        for tool in tools {
            if let path = resolve(tool.binary) { found[tool.id] = path }
        }
        return found
    }

    public static func cacheBytes(for ids: [String]) async -> Int64 {
        var total: Int64 = 0
        for tool in tools where ids.contains(tool.id) {
            guard let directory = tool.cacheDirectory else { continue }
            total += await SizeProbe.total(expandTilde(directory)).bytes
        }
        return total
    }

    public static func run(_ tool: DevTool, binaryPath: String) async -> Shell.Result {
        var environment = ProcessInfo.processInfo.environment
        let prepend = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PATH"] = prepend + ":" + (environment["PATH"] ?? "")
        return await Shell.result(binaryPath, tool.cleanArguments, timeout: 420, environment: environment)
    }
}
