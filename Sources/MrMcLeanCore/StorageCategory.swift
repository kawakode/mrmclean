import Foundation

public enum CleanAction: String, Sendable, Codable {
    case delete          // remove the selected child items
    case emptyTrash      // remove everything in Trash
    case thinSnapshots   // tmutil, needs admin
    case toolCleanup     // run each dev tool's own cleanup command
    case adminDelete     // root-owned paths, one password prompt
    case reviewOnly      // list only, no automated removal
}

/// How a category's size and cleanable children are discovered.
public enum Probe: Sendable {
    case breakdown(String)   // `du -d 1` on this directory; children become entries
    case glob(String)        // each glob match becomes one leaf entry
}

public struct StorageCategory: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let symbol: String
    public let blurb: String
    public let probes: [Probe]
    public let action: CleanAction
    /// Caches and logs are removed outright. Everything else moves to the Trash
    /// unless the user opts into hard deletes.
    public let hardByDefault: Bool

    public static func == (lhs: StorageCategory, rhs: StorageCategory) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var supportsAlerts: Bool {
        action != .reviewOnly && id != "snapshots"
    }
}

public enum Catalog {
    public static let all: [StorageCategory] = [
        userCaches, systemCaches, appLogs, trash, snapshots,
        developer, devTools, mailDownloads, iosBackups, largeFiles,
    ]

    public static func category(_ id: String) -> StorageCategory? {
        all.first { $0.id == id }
    }

    public static let userCaches = StorageCategory(
        id: "userCaches",
        name: "User Caches",
        symbol: "shippingbox",
        blurb: "App caches in your Library. Safe to clear; apps rebuild them on demand.",
        probes: [
            .breakdown("~/Library/Caches"),
            .glob("~/Library/Containers/*/Data/Library/Caches"),
        ],
        action: .delete,
        hardByDefault: true
    )

    public static let systemCaches = StorageCategory(
        id: "systemCaches",
        name: "System Caches & Logs",
        symbol: "gearshape",
        blurb: "Root-owned caches, diagnostic reports and crash logs. Needs an administrator password.",
        probes: [
            .breakdown("/Library/Caches"),
            .breakdown("/Library/Logs"),
            .breakdown("/Library/Application Support/CrashReporter"),
        ],
        action: .adminDelete,
        hardByDefault: true
    )

    public static let appLogs = StorageCategory(
        id: "appLogs",
        name: "App Logs",
        symbol: "doc.text",
        blurb: "Diagnostic logs written by your apps.",
        probes: [.breakdown("~/Library/Logs")],
        action: .delete,
        hardByDefault: true
    )

    public static let trash = StorageCategory(
        id: "trash",
        name: "Trash",
        symbol: "trash",
        blurb: "Items sitting in the Trash.",
        probes: [.breakdown("~/.Trash")],
        action: .emptyTrash,
        hardByDefault: true
    )

    public static let snapshots = StorageCategory(
        id: "snapshots",
        name: "Time Machine Snapshots",
        symbol: "clock.arrow.circlepath",
        blurb: "Local APFS snapshots. macOS purges these under pressure; thinning frees the space now. Needs an administrator password.",
        probes: [],
        action: .thinSnapshots,
        hardByDefault: true
    )

    public static let developer = StorageCategory(
        id: "developer",
        name: "Xcode & Developer",
        symbol: "hammer",
        blurb: "Derived data, archives, old device support and simulator caches.",
        probes: [
            .breakdown("~/Library/Developer/Xcode/DerivedData"),
            .breakdown("~/Library/Developer/Xcode/Archives"),
            .breakdown("~/Library/Developer/Xcode/iOS DeviceSupport"),
            .breakdown("~/Library/Developer/Xcode/watchOS DeviceSupport"),
            .breakdown("~/Library/Developer/CoreSimulator/Caches"),
        ],
        action: .delete,
        hardByDefault: true
    )

    public static let devTools = StorageCategory(
        id: "devTools",
        name: "Dev Tool Caches",
        symbol: "terminal",
        blurb: "Package manager and build tool caches, cleared with each tool's own command.",
        probes: [],
        action: .toolCleanup,
        hardByDefault: false
    )

    public static let mailDownloads = StorageCategory(
        id: "mailDownloads",
        name: "Mail Downloads",
        symbol: "envelope",
        blurb: "Attachments saved by Mail. Clearing them does not remove the messages.",
        probes: [.breakdown("~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads")],
        action: .delete,
        hardByDefault: false
    )

    public static let iosBackups = StorageCategory(
        id: "iosBackups",
        name: "iOS Backups",
        symbol: "iphone",
        blurb: "Local backups of iOS and iPadOS devices. Review carefully; deleted backups cannot be recovered.",
        probes: [.breakdown("~/Library/Application Support/MobileSync/Backup")],
        action: .reviewOnly,
        hardByDefault: false
    )

    public static let largeFiles = StorageCategory(
        id: "largeFiles",
        name: "Large Files",
        symbol: "doc.viewfinder",
        blurb: "Files over 1 GB in your home folder. Scanned on request. Review and remove in Finder.",
        probes: [],
        action: .reviewOnly,
        hardByDefault: false
    )
}
