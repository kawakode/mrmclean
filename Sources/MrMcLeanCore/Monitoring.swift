import Foundation

public struct LowStorageConfig: Codable, Equatable, Sendable {
    public enum Unit: String, Codable, CaseIterable, Sendable { case percent, gigabytes }
    public var isEnabled = false
    public var unit: Unit = .percent
    public var threshold: Double = 10
    public var lastAlertDate: Date?
    public init() {}

    public func shouldNotify(disk: DiskInfo, alertsEnabled: Bool, cooldownHours: Double, now: Date = Date()) -> Bool {
        guard alertsEnabled, isEnabled, disk.totalBytes > 0, disk.availableBytes >= 0,
              threshold.isFinite, threshold > 0, unit != .percent || threshold <= 100 else { return false }
        let free = unit == .percent ? Double(disk.availableBytes) / Double(disk.totalBytes) * 100
                                   : Double(disk.availableBytes) / 1_000_000_000
        guard free <= threshold else { return false }
        return lastAlertDate.map { now.timeIntervalSince($0) >= max(0, cooldownHours) * 3600 } ?? true
    }
}

/// The label describes the app owning a folder; this is folder activity, not
/// process attribution. Existing files establish a baseline on the first scan.
public struct ActivityAlertConfig: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "App logs"
    public var folder = ""
    public var isEnabled = false
    public var includesSubfolders = true
    public var windowMinutes: Double = 5
    public var fileCountEnabled = true
    public var fileCountThreshold = 100
    public var growthEnabled = true
    public var growthMB: Double = 100
    public var lastAlertDate: Date?
    public init() {}

    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this alert an app or folder name." }
        if folder.isEmpty { return "Choose the folder to monitor." }
        if !windowMinutes.isFinite || windowMinutes < 1 || windowMinutes > 60 { return "Choose a window of 1–60 minutes." }
        if !fileCountEnabled && !growthEnabled { return "Enable a file-count or growth threshold." }
        if fileCountEnabled && fileCountThreshold < 1 { return "The file-count threshold must be positive." }
        if growthEnabled && (!growthMB.isFinite || growthMB <= 0) { return "The growth threshold must be positive." }
        return nil
    }

    public var monitoringConfig: Self {
        var copy = self
        copy.lastAlertDate = nil
        return copy
    }
}

public struct ActivityEvaluation: Sendable {
    public var newFiles: Int
    public var growthBytes: Int64
    public var shouldNotify: Bool
}

public struct ActivityTracker: Sendable {
    private struct Event: Sendable {
        var date: Date
        var count: Int
        var bytes: Int64
    }
    private var baseline: [String: Int64]?
    private var lastSample: Date?
    private var events: [Event] = []
    private var configuration: ActivityAlertConfig?
    public init() {}

    public mutating func observe(_ scan: ManagedFileScan, config: ActivityAlertConfig,
                                 alertsEnabled: Bool, cooldownHours: Double, now: Date = Date()) -> ActivityEvaluation? {
        guard scan.issues.isEmpty, config.validationError == nil, config.isEnabled, alertsEnabled else {
            self = ActivityTracker()
            return nil
        }
        if configuration != config.monitoringConfig {
            self = ActivityTracker()
            configuration = config.monitoringConfig
        }
        var current: [String: Int64] = [:]
        for file in scan.files { current[file.identity] = max(0, file.bytes) }
        let window = config.windowMinutes * 60
        // Sleeping, failed scans and restarts cannot turn historical files into a burst.
        if lastSample.map({ now.timeIntervalSince($0) > window + 30 || now < $0 }) == true {
            baseline = nil
            events = []
        }
        defer { baseline = current; lastSample = now }
        guard let baseline else { return nil }
        var count = 0
        var growth: Int64 = 0
        for (identity, bytes) in current {
            if baseline[identity] == nil { count += 1 }
            let added = max(0, bytes - (baseline[identity] ?? 0))
            growth = addingClamped(growth, added)
        }
        events.append(Event(date: now, count: count, bytes: growth))
        events.removeAll { now.timeIntervalSince($0.date) >= window }
        let totalCount = events.reduce(0) { $0 + $1.count }
        let totalBytes = events.reduce(Int64(0)) { addingClamped($0, $1.bytes) }
        let overThreshold = (config.fileCountEnabled && totalCount >= config.fileCountThreshold)
            || (config.growthEnabled && Double(totalBytes) >= config.growthMB * 1_000_000)
        let cooledDown = config.lastAlertDate.map { now.timeIntervalSince($0) >= max(0, cooldownHours) * 3600 } ?? true
        return ActivityEvaluation(newFiles: totalCount, growthBytes: totalBytes,
                                  shouldNotify: overThreshold && cooledDown)
    }

    private func addingClamped(_ left: Int64, _ right: Int64) -> Int64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        return overflow ? Int64.max : sum
    }
}
