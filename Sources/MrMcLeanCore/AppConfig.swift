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
    public var automationEnabled = false
    public var ruleIntervalMinutes: Double = 5
    public var fileRules: [FileRule] = []
    public var lowStorage = LowStorageConfig()
    public var activityAlerts: [ActivityAlertConfig] = []
    public var monitoringIntervalSeconds: Double = 60

    public init() {}

    // Decode fields individually so adding features preserves every existing setting.
    private enum CodingKeys: String, CodingKey {
        case categories, alertsEnabled, scanIntervalHours, cooldownHours, reAlertGrowthPercent
        case showDockIcon, launchMinimized, hardDeleteNonCache, enabledDevTools
        case automationEnabled, ruleIntervalMinutes, fileRules, lowStorage, activityAlerts, monitoringIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent([String: CategoryConfig].self, forKey: .categories) ?? categories
        alertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? alertsEnabled
        scanIntervalHours = try c.decodeIfPresent(Double.self, forKey: .scanIntervalHours) ?? scanIntervalHours
        cooldownHours = try c.decodeIfPresent(Double.self, forKey: .cooldownHours) ?? cooldownHours
        reAlertGrowthPercent = try c.decodeIfPresent(Double.self, forKey: .reAlertGrowthPercent) ?? reAlertGrowthPercent
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? showDockIcon
        launchMinimized = try c.decodeIfPresent(Bool.self, forKey: .launchMinimized) ?? launchMinimized
        hardDeleteNonCache = try c.decodeIfPresent(Bool.self, forKey: .hardDeleteNonCache) ?? hardDeleteNonCache
        enabledDevTools = try c.decodeIfPresent(Set<String>.self, forKey: .enabledDevTools) ?? enabledDevTools
        automationEnabled = try c.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? automationEnabled
        ruleIntervalMinutes = try c.decodeIfPresent(Double.self, forKey: .ruleIntervalMinutes) ?? ruleIntervalMinutes
        fileRules = try c.decodeIfPresent([FileRule].self, forKey: .fileRules) ?? fileRules
        lowStorage = try c.decodeIfPresent(LowStorageConfig.self, forKey: .lowStorage) ?? lowStorage
        activityAlerts = try c.decodeIfPresent([ActivityAlertConfig].self, forKey: .activityAlerts) ?? activityAlerts
        monitoringIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .monitoringIntervalSeconds) ?? monitoringIntervalSeconds
    }

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
