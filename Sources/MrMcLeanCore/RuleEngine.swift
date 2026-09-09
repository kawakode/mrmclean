import Foundation
import Darwin

public struct RuleReceipt: Codable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, completed, failed }
    public var id = UUID()
    public var ruleID: UUID
    public var revision: String
    public var fileIdentity: String
    public var ruleName: String
    public var path: String
    public var date: Date
    public var status: Status
    public var detail: String
}

public struct RuleJournal: Codable, Sendable {
    public var receipts: [RuleReceipt] = []
    public init() {}

    public static var fileURL: URL { AppConfig.fileURL.deletingLastPathComponent().appendingPathComponent("rule-history.jsonl") }

    public static func load(from url: URL = Self.fileURL) throws -> RuleJournal {
        guard FileManager.default.fileExists(atPath: url.path) else { return RuleJournal() }
        let data = try Data(contentsOf: url)
        guard data.isEmpty || data.last == 10 else { throw FileManagementError("Execution history has an incomplete write.") }
        var journal = RuleJournal()
        var indices: [UUID: Int] = [:]
        for line in data.split(separator: 10) {
            let receipt = try JSONDecoder().decode(RuleReceipt.self, from: Data(line))
            if let index = indices[receipt.id] { journal.receipts[index] = receipt }
            else {
                indices[receipt.id] = journal.receipts.count
                journal.receipts.append(receipt)
            }
        }
        return journal
    }

    /// Append the current file's receipt and flush it before allowing a mutation.
    /// Appending avoids quadratic writes when a folder contains thousands of files.
    public func save(to url: URL = Self.fileURL) throws {
        guard let receipt = receipts.last else { return }
        var data = try JSONEncoder().encode(receipt)
        data.append(10)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                written += count
            }
        }
        guard fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    public func handledIdentities(for rule: FileRule) -> Set<String> {
        let revision = rule.revision
        return Set(receipts.filter { $0.ruleID == rule.id && $0.revision == revision }.map(\.fileIdentity))
    }
}

public enum PlannedFileAction: Sendable {
    case move(URL), rename(URL), tag(String), trash

    public var description: String {
        switch self {
        case .move(let url): return "Move → \(url.path)"
        case .rename(let url): return "Rename → \(url.lastPathComponent)"
        case .tag(let tag): return "Add tag “\(tag)”"
        case .trash: return "Move to Trash"
        }
    }
}

public struct PlannedFile: Identifiable, Sendable {
    public var id: String { file.url.path }
    public var file: FileMetadata
    public var actions: [PlannedFileAction]
    public var problem: String?

    public init(file: FileMetadata, actions: [PlannedFileAction], problem: String? = nil) {
        self.file = file
        self.actions = actions
        self.problem = problem
    }
}

public struct RulePreview: Sendable {
    public var rule: FileRule
    public var root: URL?
    public var files: [PlannedFile] = []
    public var issues: [String] = []
    public var alreadyHandled = 0
    public var settling = 0
    public var actionableCount: Int { files.filter { $0.problem == nil && !$0.actions.isEmpty }.count }

    public init(rule: FileRule, root: URL? = nil, files: [PlannedFile] = []) {
        self.rule = rule
        self.root = root
        self.files = files
    }
}

public struct RuleRunResult: Sendable {
    public var completed = 0
    public var issues: [String] = []
    public var historyFailure: String?
    public init() {}
}

public enum RuleEngine {
    public static func preview(rule: FileRule, journal: RuleJournal, now: Date = Date()) -> RulePreview {
        var result = RulePreview(rule: rule)
        if let error = rule.validationError { result.issues = [error]; return result }
        do { result.root = try ManagedFolder.resolve(rule.folder) }
        catch { result.issues = [error.localizedDescription]; return result }
        let scan = ManagedFiles.scan(folder: rule.folder, recursive: rule.includesSubfolders)
        result.issues = scan.issues
        let handled = journal.handledIdentities(for: rule)
        var destinations = Set<String>()
        for file in scan.files where rule.matches(file, now: now) {
            if handled.contains(file.identity) { result.alreadyHandled += 1; continue }
            // Leave active writes and incomplete downloads alone.
            if now.timeIntervalSince(file.modified) < 30 || ["download", "crdownload", "part", "tmp"].contains(file.url.pathExtension.lowercased()) {
                result.settling += 1
                continue
            }
            var planned = PlannedFile(file: file, actions: [])
            do {
                planned.actions = try plan(rule.actions, for: file)
                for action in planned.actions {
                    switch action {
                    case .move(let target), .rename(let target):
                        guard destinations.insert(target.path).inserted else {
                            throw FileManagementError("Another matching file has the same destination: \(target.path)")
                        }
                    default: break
                    }
                }
            } catch { planned.problem = error.localizedDescription }
            result.files.append(planned)
        }
        return result
    }

    private static func plan(_ actions: [FileAction], for file: FileMetadata) throws -> [PlannedFileAction] {
        var planned: [PlannedFileAction] = []
        var current = file.url
        for action in actions {
            switch action.kind {
            case .tag:
                if !file.tags.contains(action.value) { planned.append(.tag(action.value)) }
            case .rename:
                let name = FileRuleTemplate.render(action.value, file: file)
                try validateRenderedPath(name, allowsFolders: false)
                let target = current.deletingLastPathComponent().appendingPathComponent(name)
                if target.path != current.path {
                    try ensureVacant(target)
                    planned.append(.rename(target))
                    current = target
                }
            case .move:
                let root = try ManagedFolder.resolve(action.value)
                let destinationDevice = try FileManager.default.attributesOfItem(atPath: root.path)[.systemNumber] as? NSNumber
                guard destinationDevice?.stringValue == file.identity.split(separator: ":").first.map(String.init) else {
                    throw FileManagementError("Automatic moves must stay on the same volume to preserve file identity and prevent repeated rules.")
                }
                let relative = FileRuleTemplate.render(action.subfolder, file: file)
                if !relative.isEmpty { try validateRenderedPath(relative, allowsFolders: true) }
                let folder = relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
                try validateDestination(folder, root: root)
                let target = folder.appendingPathComponent(current.lastPathComponent)
                if target.path != current.path {
                    try ensureVacant(target)
                    planned.append(.move(target))
                    current = target
                }
            case .trash: planned.append(.trash)
            }
        }
        return planned
    }

    private static func validateRenderedPath(_ path: String, allowsFolders: Bool) throws {
        // Braces in a real filename are literal; only templates interpret them.
        let literal = path.replacingOccurrences(of: "{", with: "_").replacingOccurrences(of: "}", with: "_")
        guard FileRuleTemplate.isValid(literal, allowsFolders: allowsFolders),
              !path.isEmpty, path.split(separator: "/").allSatisfy({ $0.utf8.count <= 255 }) else {
            throw FileManagementError("The resulting filename or subfolder is invalid: \(path)")
        }
    }

    private static func ensureVacant(_ url: URL) throws {
        // attributesOfItem also detects dangling symlinks, which fileExists does not.
        if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
            throw FileManagementError("Destination already exists: \(url.path)")
        }
    }

    private static func validateDestination(_ folder: URL, root: URL) throws {
        guard folder.path == root.path || folder.path.hasPrefix(root.path + "/"),
              !folder.pathComponents.contains(".."),
              try ManagedFolder.resolve(root.path).path == root.path else {
            throw FileManagementError("Destination leaves the chosen folder or uses a symbolic link.")
        }
        var existing = folder
        while !FileManager.default.fileExists(atPath: existing.path) && existing.path != root.path {
            if (try? FileManager.default.attributesOfItem(atPath: existing.path)) != nil {
                throw FileManagementError("Destination contains a symbolic link.")
            }
            existing.deleteLastPathComponent()
        }
        guard try ManagedFolder.resolve(existing.path).path == existing.path else {
            throw FileManagementError("Destination contains a symbolic link.")
        }
    }

    /// Revalidates the preview and saves a receipt BEFORE changing a file. A crash
    /// or partially failed action sequence is never blindly retried on the next tick.
    /// The injected persistence and Trash operations keep tests in disposable fixtures.
    public static func execute(_ preview: RulePreview, journal: inout RuleJournal,
                               persist: (RuleJournal) throws -> Void,
                               trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> RuleRunResult {
        var result = RuleRunResult()
        guard preview.issues.isEmpty, let root = preview.root else {
            result.issues = preview.issues
            return result
        }
        do {
            guard try ManagedFolder.resolve(preview.rule.folder).path == root.path else {
                throw FileManagementError("The rule’s folder changed after the preview.")
            }
        } catch { result.issues = [error.localizedDescription]; return result }
        var handled = journal.handledIdentities(for: preview.rule)
        for item in preview.files {
            if Task.isCancelled { break }
            if let problem = item.problem { result.issues.append("\(item.file.url.path): \(problem)"); continue }
            guard !item.actions.isEmpty, !handled.contains(item.file.identity) else { continue }
            do {
                try ManagedFolder.validateFile(item.file.url, in: root)
                let fresh = try FileMetadata.read(URL(fileURLWithPath: item.file.url.path))
                guard fresh.identity == item.file.identity, fresh.bytes == item.file.bytes,
                      fresh.modified == item.file.modified, fresh.tags == item.file.tags,
                      preview.rule.matches(fresh) else {
                    throw FileManagementError("File changed since the preview; it was skipped.")
                }
                // Re-plan to catch destinations changed since preview.
                let actions = try plan(preview.rule.actions, for: fresh)
                guard actions.map(\.description) == item.actions.map(\.description) else {
                    throw FileManagementError("Actions changed since the preview; preview again.")
                }
                var receipt = RuleReceipt(ruleID: preview.rule.id, revision: preview.rule.revision,
                    fileIdentity: fresh.identity, ruleName: preview.rule.name, path: fresh.url.path,
                    date: Date(), status: .pending, detail: actions.map(\.description).joined(separator: " · "))
                journal.receipts.append(receipt)
                do { try persist(journal) }
                catch {
                    journal.receipts.removeLast()
                    result.historyFailure = "Could not save execution history. Rules are paused: \(error.localizedDescription)"
                    result.issues.append(result.historyFailure!)
                    return result
                }
                handled.insert(fresh.identity)
                var current = fresh.url
                do {
                    for action in actions {
                        // Check the current path again before each mutation.
                        let currentRoot = try ManagedFolder.resolve(current.deletingLastPathComponent().path)
                        try ManagedFolder.validateFile(current, in: currentRoot)
                        let currentFile = try FileMetadata.read(URL(fileURLWithPath: current.path))
                        guard currentFile.identity == receipt.fileIdentity, currentFile.bytes == fresh.bytes,
                              currentFile.modified == fresh.modified else {
                            throw FileManagementError("File changed during the rule; remaining actions skipped.")
                        }
                        switch action {
                        case .tag(let tag):
                            // NSURL supports setting Finder tags on macOS 14; the
                            // Swift URLResourceValues setter requires macOS 26.
                            try (URL(fileURLWithPath: current.path) as NSURL).setResourceValue(
                                Array(Set(currentFile.tags + [tag])).sorted(), forKey: .tagNamesKey)
                        case .rename(let target), .move(let target):
                            // Both destinations were already checked against their selected scope.
                            let moveRoot = preview.rule.actions.first(where: { $0.kind == .move })
                                .flatMap { try? ManagedFolder.resolve($0.value) }
                            let destinationRoot = target.deletingLastPathComponent().path == current.deletingLastPathComponent().path
                                ? currentRoot : (moveRoot ?? root)
                            try validateDestination(target.deletingLastPathComponent(), root: destinationRoot)
                            let device = try FileManager.default.attributesOfItem(atPath: destinationRoot.path)[.systemNumber] as? NSNumber
                            guard device?.stringValue == fresh.identity.split(separator: ":").first.map(String.init) else {
                                throw FileManagementError("Destination volume changed; move skipped.")
                            }
                            try ensureVacant(target)
                            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try validateDestination(target.deletingLastPathComponent(), root: destinationRoot)
                            try FileManager.default.moveItem(at: current, to: target)
                            current = target
                        case .trash: try trash(current)
                        }
                    }
                    receipt.status = .completed
                    receipt.path = current.path
                    result.completed += 1
                } catch {
                    receipt.status = .failed
                    receipt.path = current.path
                    receipt.detail += "\n\(error.localizedDescription)"
                    result.issues.append("\(current.path): \(error.localizedDescription)")
                }
                // Update the original reservation; same-volume moves retain identity.
                if let index = journal.receipts.firstIndex(where: { $0.id == receipt.id }) {
                    journal.receipts[index] = receipt
                }
                do { try persist(journal) }
                catch {
                    result.historyFailure = "Could not update execution history. Rules are paused: \(error.localizedDescription)"
                    result.issues.append(result.historyFailure!)
                    break
                }
            } catch { result.issues.append("\(item.file.url.path): \(error.localizedDescription)") }
        }
        return result
    }
}
