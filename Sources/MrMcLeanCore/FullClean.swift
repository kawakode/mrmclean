import Foundation

/// One unit of work in a full clean, in execution order.
public struct FullCleanStep: Sendable, Identifiable {
    public enum Work: Sendable, Equatable {
        /// Delete the scanned entries of this catalog category through the allowlist.
        case userCategory(String)
        /// Run each listed dev tool's own cleanup command.
        case devTools([String])
        /// Run the one authenticated system cleanup script.
        case system(includeSnapshots: Bool)
    }

    public let id: String
    public let title: String
    public let symbol: String
    public let work: Work

    public init(id: String, title: String, symbol: String, work: Work) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.work = work
    }
}

public enum FullClean {
    /// The safe, no-password categories a full clean always removes, in order.
    public static let safeCategoryIDs = ["userCaches", "appLogs", "developer", "trash"]

    /// Build the ordered step list for a full clean.
    /// - Parameters:
    ///   - includeSystem: also run the authenticated system cleanup (root-owned
    ///     caches, logs, crash reports, and optionally snapshots).
    ///   - includeSnapshots: thin Time Machine local snapshots as part of the
    ///     system step. Ignored when `includeSystem` is false.
    ///   - devToolIDs: dev tools to clean, normally the user's enabled set. An
    ///     empty list drops the dev-tools step entirely.
    public static func plan(includeSystem: Bool,
                            includeSnapshots: Bool = true,
                            devToolIDs: [String] = []) -> [FullCleanStep] {
        var steps: [FullCleanStep] = [
            FullCleanStep(id: "userCaches", title: "User caches", symbol: "shippingbox",
                          work: .userCategory("userCaches")),
            FullCleanStep(id: "appLogs", title: "App logs", symbol: "doc.text",
                          work: .userCategory("appLogs")),
            FullCleanStep(id: "developer", title: "Xcode & developer files", symbol: "hammer",
                          work: .userCategory("developer")),
            FullCleanStep(id: "trash", title: "Trash", symbol: "trash",
                          work: .userCategory("trash")),
        ]
        if !devToolIDs.isEmpty {
            steps.append(FullCleanStep(id: "devTools", title: "Dev tool caches", symbol: "terminal",
                                       work: .devTools(devToolIDs)))
        }
        if includeSystem {
            steps.append(FullCleanStep(
                id: "system",
                title: includeSnapshots ? "System caches & snapshots" : "System caches & logs",
                symbol: "gearshape",
                work: .system(includeSnapshots: includeSnapshots)
            ))
        }
        return steps
    }
}

/// The running state and final tally of one full clean, shown live and then as a
/// report.
public struct FullCleanPhase: Sendable, Identifiable, Equatable {
    public enum Status: String, Sendable { case pending, running, done, failed, skipped }

    public let id: String
    public let title: String
    public let symbol: String
    public var status: Status = .pending
    public var freedBytes: Int64 = 0
    public var removedCount: Int = 0
    public var skippedCount: Int = 0
    /// Set when the figure is an estimate rather than a measured deletion, or to
    /// carry a short failure reason.
    public var note: String? = nil

    public init(id: String, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

public struct FullCleanReport: Sendable {
    public var phases: [FullCleanPhase]
    public var startedAt: Date
    public var finishedAt: Date?
    public var diskBefore: DiskInfo
    public var diskAfter: DiskInfo?

    public init(phases: [FullCleanPhase],
                startedAt: Date = Date(),
                diskBefore: DiskInfo,
                finishedAt: Date? = nil,
                diskAfter: DiskInfo? = nil) {
        self.phases = phases
        self.startedAt = startedAt
        self.diskBefore = diskBefore
        self.finishedAt = finishedAt
        self.diskAfter = diskAfter
    }

    public var totalFreedBytes: Int64 { phases.reduce(0) { $0 + $1.freedBytes } }
    public var totalRemoved: Int { phases.reduce(0) { $0 + $1.removedCount } }
    public var totalSkipped: Int { phases.reduce(0) { $0 + $1.skippedCount } }
    public var anyFailed: Bool { phases.contains { $0.status == .failed } }

    /// Real free-space gain measured from the volume, when both readings exist.
    /// Preferred over `totalFreedBytes` for the headline number.
    public var diskFreedBytes: Int64? {
        guard let after = diskAfter else { return nil }
        return max(0, after.availableBytes - diskBefore.availableBytes)
    }

    /// The best number to show the user: the measured volume delta if we have it
    /// and it is positive, otherwise the sum of the per-phase figures.
    public var headlineFreedBytes: Int64 {
        if let measured = diskFreedBytes, measured > 0 { return measured }
        return totalFreedBytes
    }

    public var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    public var isComplete: Bool { finishedAt != nil }

    public var resolvedPhaseCount: Int {
        phases.filter { $0.status == .done || $0.status == .failed || $0.status == .skipped }.count
    }

    /// 0...1 fraction of phases that have finished, for the progress ring.
    public var progress: Double {
        phases.isEmpty ? 0 : Double(resolvedPhaseCount) / Double(phases.count)
    }

    public mutating func update(_ id: String, _ mutate: (inout FullCleanPhase) -> Void) {
        guard let index = phases.firstIndex(where: { $0.id == id }) else { return }
        mutate(&phases[index])
    }
}
