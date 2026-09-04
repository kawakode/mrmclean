import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Whether the app can read TCC-protected locations.
///
/// Full Disk Access has no programmatic prompt and no Info.plist purpose string:
/// the user grants it by hand in System Settings. All we can do is detect the
/// current state by trying to open a file that only an app holding the grant may
/// read, and point the user at the right settings pane.
public enum FullDiskAccessStatus: String, Sendable {
    case granted
    case denied
    /// No protected probe file was present, so the state could not be decided.
    case unknown
}

public enum FullDiskAccess {
    /// System Settings deep link to the Full Disk Access list.
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Files that exist on a stock macOS 14+ install and are readable only with
    /// Full Disk Access. The user copy of `TCC.db` is always present; the others
    /// are fallbacks for the rare case it is missing.
    static var probePaths: [String] {
        [
            userHome + "/Library/Application Support/com.apple.TCC/TCC.db",
            userHome + "/Library/Safari/Bookmarks.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
    }

    public static func check() -> FullDiskAccessStatus {
        var sawProtectedFile = false
        for path in probePaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            sawProtectedFile = true
            let descriptor = open(path, O_RDONLY)
            if descriptor >= 0 {
                close(descriptor)
                return .granted
            }
            // EPERM/EACCES is the TCC denial. Anything else (file locked, busy)
            // is inconclusive, so keep trying the remaining probes.
        }
        return sawProtectedFile ? .denied : .unknown
    }
}
