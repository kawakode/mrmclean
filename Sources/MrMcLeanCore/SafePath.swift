import Foundation

public enum SafePathError: Error, CustomStringConvertible, Equatable {
    case emptyPath
    case traversal(String)
    case forbidden(String)
    case outsideAllowlist(String)

    public var description: String {
        switch self {
        case .emptyPath:
            return "Empty path."
        case .traversal(let path):
            return "Path contains a parent reference: \(path)"
        case .forbidden(let path):
            return "Path is in a protected location: \(path)"
        case .outsideAllowlist(let path):
            return "Path is outside the cleanable allowlist: \(path)"
        }
    }
}

/// The single gate every user-level deletion passes through.
public enum SafePath {
    public static let home = userHome

    public static var allowedRoots: [String] {
        [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/.Trash",
            "\(home)/Library/Developer",
            "\(home)/Library/Containers",
            "\(home)/Library/Application Support/CrashReporter",
            "\(home)/Library/Caches/Homebrew",
            "\(home)/Library/pnpm/store",
            "\(home)/.npm",
            "\(home)/go/pkg/mod",
        ]
    }

    public static var forbiddenRoots: [String] {
        [
            "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib",
            "/Library/Apple", "/private/etc", "/etc", "/private/var/db", "/var/db",
            "\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads",
            "\(home)/Movies", "\(home)/Music", "\(home)/Pictures", "\(home)/Public",
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/Application Support/MobileSync",
            "\(home)/Library/Messages", "\(home)/Library/Mail",
        ]
    }

    public static func validate(_ rawPath: String) throws {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SafePathError.emptyPath }
        if trimmed.split(separator: "/").contains("..") {
            throw SafePathError.traversal(trimmed)
        }

        let standardized = (expandTilde(trimmed) as NSString).standardizingPath
        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        let path = (resolved.count > 1 && resolved.hasSuffix("/")) ? String(resolved.dropLast()) : resolved

        if path == "/" || path == home {
            throw SafePathError.forbidden(path)
        }
        for root in forbiddenRoots where path == root || path.hasPrefix(root + "/") {
            throw SafePathError.forbidden(path)
        }

        let underAllowedRoot = allowedRoots.contains { path.hasPrefix($0 + "/") }
        guard underAllowedRoot else { throw SafePathError.outsideAllowlist(path) }

        if path.hasPrefix("\(home)/Library/Containers/") {
            let relative = String(path.dropFirst("\(home)/Library/Containers/".count))
            let components = relative.split(separator: "/")
            let isCache = components.count >= 4
                && components[1...3].map(String.init) == ["Data", "Library", "Caches"]
            let mailDownloads = "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
            guard isCache || path.hasPrefix(mailDownloads + "/") else {
                throw SafePathError.outsideAllowlist(path)
            }
        }
        if path.hasPrefix("\(home)/Library/Developer/") {
            let allowedDeveloperSubtrees = [
                "Xcode/DerivedData", "Xcode/Archives",
                "Xcode/iOS DeviceSupport", "Xcode/watchOS DeviceSupport",
                "Xcode/tvOS DeviceSupport", "CoreSimulator/Caches",
            ]
            let ok = allowedDeveloperSubtrees.contains {
                path.hasPrefix("\(home)/Library/Developer/\($0)/")
            }
            guard ok else { throw SafePathError.outsideAllowlist(path) }
        }
    }

    public static func isValid(_ path: String) -> Bool {
        (try? validate(path)) != nil
    }
}
