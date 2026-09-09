import Foundation
import Darwin
import UniformTypeIdentifiers

public struct FileManagementError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ManagedFileKind: String, CaseIterable, Sendable {
    case image, audio, video, document, archive, other
}

public struct FileMetadata: Sendable, Equatable {
    public var url: URL
    public var identity: String
    public var bytes: Int64
    public var created: Date
    public var modified: Date
    public var opened: Date?
    public var tags: [String]
    public var kind: ManagedFileKind

    public init(url: URL, identity: String, bytes: Int64, created: Date, modified: Date,
                opened: Date? = nil, tags: [String] = [], kind: ManagedFileKind = .other) {
        self.url = url
        self.identity = identity
        self.bytes = bytes
        self.created = created
        self.modified = modified
        self.opened = opened
        self.tags = tags
        self.kind = kind
    }

    public static func read(_ url: URL) throws -> FileMetadata {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber,
              let created = attributes[.creationDate] as? Date,
              let modified = attributes[.modificationDate] as? Date else {
            throw FileManagementError("Only regular files with a single hard link are supported: \(url.path)")
        }
        let values = try url.resourceValues(forKeys: [.tagNamesKey, .contentAccessDateKey, .contentTypeKey])
        let type = values.contentType
        let kind: ManagedFileKind
        if type?.conforms(to: .image) == true { kind = .image }
        else if type?.conforms(to: .audio) == true { kind = .audio }
        else if type?.conforms(to: .movie) == true { kind = .video }
        else if type?.conforms(to: .archive) == true { kind = .archive }
        else if type?.conforms(to: .text) == true || type?.conforms(to: .pdf) == true
                    || type?.conforms(to: .content) == true { kind = .document }
        else { kind = .other }
        return FileMetadata(url: url, identity: "\(device):\(inode):\(created.timeIntervalSince1970)",
                            bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                            created: created, modified: modified, opened: values.contentAccessDate,
                            tags: values.tagNames ?? [], kind: kind)
    }
}

/// Scope for opt-in file rules, separate from the cleaner's deletion allowlist.
/// No system folders, Trash, app bundles, library databases, symlinks or root-wide rules.
public enum ManagedFolder {
    /// Unlike Foundation's URL normalization, realpath preserves the canonical
    /// /private/var path returned by directory enumeration on macOS.
    public static func canonical(_ url: URL) throws -> URL {
        guard let pointer = realpath(url.path, nil) else {
            throw FileManagementError("\(url.path): \(String(cString: strerror(errno)))")
        }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer))
    }

    public static func resolve(_ path: String, readOnly: Bool = false) throws -> URL {
        let expanded = expandTilde(path)
        guard expanded.hasPrefix("/"), !expanded.split(separator: "/").contains(".."),
              !expanded.contains("\0") else { throw FileManagementError("Choose an absolute folder path without parent references.") }
        let url = try canonical(URL(fileURLWithPath: expanded))
        let home = try canonical(URL(fileURLWithPath: userHome)).path
        let temp = try canonical(FileManager.default.temporaryDirectory).path
        let inHome = url.path.hasPrefix(home + "/")
        let inTemp = url.path.hasPrefix(temp.hasSuffix("/") ? temp : temp + "/") && url.path != temp
        let onVolume = url.path.hasPrefix("/Volumes/") && url.pathComponents.count > 3
        guard inHome || inTemp || onVolume else {
            throw FileManagementError("Choose a specific folder in your home folder or on an external volume.")
        }
        if !readOnly && inHome && (url.path == home + "/Library" || url.path.hasPrefix(home + "/Library/")) {
            let allowed = [home + "/Library/Logs", home + "/Library/Caches"]
            guard allowed.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else {
                throw FileManagementError("Rules can manage Library/Logs and Library/Caches; other Library data is protected.")
            }
        }
        var component = url
        while component.path != "/" {
            guard (readOnly || !component.lastPathComponent.hasPrefix(".")), component.lastPathComponent != ".Trash" else {
                throw FileManagementError("Hidden folders and the Trash cannot be managed.")
            }
            let values = try component.resourceValues(forKeys: [.isPackageKey, .isDirectoryKey])
            guard values.isPackage != true, directoryExists(component.path) else {
                throw FileManagementError("Choose an existing folder outside an app or document package.")
            }
            component.deleteLastPathComponent()
        }
        return url
    }

    public static func validateFile(_ url: URL, in root: URL) throws {
        guard url.path.hasPrefix(root.path + "/"),
              !url.pathComponents.contains(".."),
              try canonical(url).path == url.path else {
            throw FileManagementError("File left the selected folder or is reached through a symbolic link: \(url.path)")
        }
        var parent = url.deletingLastPathComponent()
        while parent.path != root.path {
            let values = try parent.resourceValues(forKeys: [.isPackageKey, .isSymbolicLinkKey])
            guard values.isPackage != true, values.isSymbolicLink != true, !parent.lastPathComponent.hasPrefix(".") else {
                throw FileManagementError("Files inside hidden folders, packages or symbolic links are skipped.")
            }
            parent.deleteLastPathComponent()
        }
    }
}

public struct ManagedFileScan: Sendable {
    public var files: [FileMetadata] = []
    public var issues: [String] = []
    public init(files: [FileMetadata] = [], issues: [String] = []) {
        self.files = files
        self.issues = issues
    }
}

public enum ManagedFiles {
    /// Bounded enumeration. Call off the main actor. A partial result must never
    /// be used as an activity baseline or to execute rules.
    public static func scan(folder: String, recursive: Bool, limit: Int = 20_000,
                            timeout: TimeInterval = 15, readOnly: Bool = false) -> ManagedFileScan {
        var result = ManagedFileScan()
        do {
            let root = try ManagedFolder.resolve(folder, readOnly: readOnly)
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
            var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            if !recursive { options.insert(.skipsSubdirectoryDescendants) }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                options: options, errorHandler: { url, error in
                    if result.issues.count < 10 { result.issues.append("\(url.path): \(error.localizedDescription)") }
                    return true
                }) else { throw FileManagementError("Could not read \(root.path)") }
            let start = Date()
            var visited = 0
            for case let url as URL in enumerator {
                visited += 1
                if visited > limit || Date().timeIntervalSince(start) > timeout || Task.isCancelled {
                    result.issues.append("Folder scan is incomplete (limit of \(limit) entries or \(Int(timeout)) seconds). Choose a smaller folder.")
                    break
                }
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isSymbolicLink != true, values.isPackage != true else {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard values.isRegularFile == true else { continue }
                    try ManagedFolder.validateFile(url, in: root)
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if (attributes[.referenceCount] as? NSNumber)?.intValue ?? 1 > 1 { continue }
                    result.files.append(try FileMetadata.read(url))
                } catch {
                    if result.issues.count < 10 { result.issues.append("\(url.path): \(error.localizedDescription)") }
                }
            }
            result.files.sort { $0.url.path < $1.url.path }
        } catch { result.issues.append(error.localizedDescription) }
        return result
    }
}
