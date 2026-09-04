import Foundation

public struct CategoryConfig: Codable, Sendable, Equatable {
    public var alertEnabled: Bool = false
    /// Threshold expressed as a percentage of total disk size.
    public var thresholdPercent: Double = 10
    public var lastAlertDate: Date? = nil
    public var lastAlertBytes: Int64 = 0

    public init() {}
}

public struct AppConfig: Codable, Sendable, Equatable {
    public var categories: [String: CategoryConfig] = [:]
    public var alertsEnabled: Bool = true
    public var scanIntervalHours: Double = 6
    public var cooldownHours: Double = 24
    public var reAlertGrowthPercent: Double = 5
    public var showDockIcon: Bool = false
    public var launchMinimized: Bool = false
    public var hardDeleteNonCache: Bool = false
    public var enabledDevTools: Set<String> = []

    public init() {}

    public func category(_ id: String) -> CategoryConfig {
        categories[id] ?? CategoryConfig()
    }

    // MARK: Persistence

    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MrMcLean", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("config.json")
    }

    public static func load() -> AppConfig {
        guard
            let data = try? Data(contentsOf: fileURL),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
