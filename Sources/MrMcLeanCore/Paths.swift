import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Home directory, resolved once.
public let userHome = NSHomeDirectory()

/// Expand a leading `~` to the user's home directory.
public func expandTilde(_ path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else { return path }
    return userHome + path.dropFirst(1)
}

public func directoryExists(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

/// Shell-style glob. Returns absolute paths, unsorted, empty on no match.
public func globMatches(_ pattern: String) -> [String] {
    let expanded = expandTilde(pattern)
    var result = glob_t()
    defer { globfree(&result) }
    guard glob(expanded, GLOB_NOSORT, nil, &result) == 0 else { return [] }
    var paths: [String] = []
    for index in 0..<Int(result.gl_pathc) {
        if let cString = result.gl_pathv[index] {
            paths.append(String(cString: cString))
        }
    }
    return paths
}
