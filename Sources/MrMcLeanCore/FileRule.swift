import Foundation
import CryptoKit

public enum MetadataField: String, Codable, CaseIterable, Sendable {
    case name, fileExtension, kind, sizeMB, createdDays, modifiedDays, openedDays, tag

    public var title: String {
        switch self {
        case .name: return "File name"
        case .fileExtension: return "Extension"
        case .kind: return "File kind"
        case .sizeMB: return "Size (MB)"
        case .createdDays: return "Created (days ago)"
        case .modifiedDays: return "Modified (days ago)"
        case .openedDays: return "Last accessed (days ago)"
        case .tag: return "Finder tag"
        }
    }

    public var isNumber: Bool { [.sizeMB, .createdDays, .modifiedDays, .openedDays].contains(self) }
}

public enum MetadataComparison: String, Codable, CaseIterable, Sendable {
    case equals, contains, startsWith, endsWith, greaterThan, lessThan

    public var title: String {
        switch self {
        case .equals: return "is"
        case .contains: return "contains"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .greaterThan: return "is greater than"
        case .lessThan: return "is less than"
        }
    }

    public static func choices(for field: MetadataField) -> [Self] {
        field.isNumber ? [.greaterThan, .lessThan] : [.equals, .contains, .startsWith, .endsWith]
    }
}

public struct FileCondition: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var field: MetadataField = .fileExtension
    public var comparison: MetadataComparison = .equals
    public var value = "pdf"

    public init(field: MetadataField = .fileExtension, comparison: MetadataComparison = .equals, value: String = "pdf") {
        self.field = field
        self.comparison = comparison
        self.value = value
    }

    public func matches(_ file: FileMetadata, now: Date) -> Bool {
        if field.isNumber {
            guard let threshold = Double(value), threshold.isFinite, threshold >= 0 else { return false }
            let actual: Double
            switch field {
            case .sizeMB: actual = Double(file.bytes) / 1_000_000
            case .createdDays: actual = now.timeIntervalSince(file.created) / 86400
            case .modifiedDays: actual = now.timeIntervalSince(file.modified) / 86400
            case .openedDays:
                guard let opened = file.opened else { return false }
                actual = now.timeIntervalSince(opened) / 86400
            default: return false
            }
            switch comparison {
            case .greaterThan: return actual > threshold
            case .lessThan: return actual < threshold
            default: return false
            }
        }
        let candidates: [String]
        switch field {
        case .name: candidates = [file.url.lastPathComponent]
        case .fileExtension: candidates = [file.url.pathExtension]
        case .kind: candidates = [file.kind.rawValue]
        case .tag: candidates = file.tags
        default: return false
        }
        let target = value.lowercased()
        guard !target.isEmpty else { return false }
        return candidates.contains { candidate in
            let text = candidate.lowercased()
            switch comparison {
            case .equals: return text == target
            case .contains: return text.contains(target)
            case .startsWith: return text.hasPrefix(target)
            case .endsWith: return text.hasSuffix(target)
            default: return false
            }
        }
    }
}

public enum FileActionKind: String, Codable, CaseIterable, Sendable {
    case move, tag, rename, trash

    public var title: String {
        switch self {
        case .move: return "Move into folder"
        case .tag: return "Add Finder tag"
        case .rename: return "Rename"
        case .trash: return "Move to Trash"
        }
    }
}

public struct FileAction: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: FileActionKind = .tag
    /// Destination folder, tag, or full filename template, depending on kind.
    public var value = "Organized"
    /// Optional relative folders below the destination, e.g. {year}/{month}.
    public var subfolder = ""

    public init(kind: FileActionKind = .tag, value: String = "Organized", subfolder: String = "") {
        self.kind = kind
        self.value = value
        self.subfolder = subfolder
    }
}

public struct FileRule: Codable, Identifiable, Equatable, Sendable {
    public enum MatchMode: String, Codable, CaseIterable, Sendable { case all, any }
    public var id = UUID()
    public var name = "New rule"
    public var isEnabled = false
    public var folder = ""
    public var includesSubfolders = false
    public var matchMode: MatchMode = .all
    public var conditions = [FileCondition()]
    public var actions = [FileAction()]

    public init() {}

    public func matches(_ file: FileMetadata, now: Date = Date()) -> Bool {
        guard !conditions.isEmpty else { return false }
        return matchMode == .all
            ? conditions.allSatisfy { $0.matches(file, now: now) }
            : conditions.contains { $0.matches(file, now: now) }
    }

    /// Editing the behavior permits another run; renaming or toggling the rule does not.
    public var revision: String {
        var copy = self
        copy.name = ""
        copy.isEnabled = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(copy) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the rule a name." }
        if folder.isEmpty { return "Choose a folder to manage." }
        if conditions.isEmpty { return "Add at least one condition." }
        if actions.isEmpty { return "Add at least one action." }
        for condition in conditions {
            if condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Fill in every condition." }
            if !MetadataComparison.choices(for: condition.field).contains(condition.comparison) {
                return "Choose a comparison that suits the metadata field."
            }
            if condition.field.isNumber {
                guard let number = Double(condition.value), number.isFinite, number >= 0 else {
                    return "Numeric conditions need a nonnegative number."
                }
            }
        }
        if actions.contains(where: { $0.kind == .trash }) && actions.count != 1 {
            return "Move to Trash must be the rule’s only action."
        }
        if Set(actions.map(\.kind)).count != actions.count { return "Use each action only once per rule." }
        for action in actions where action.kind != .trash {
            if action.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Fill in every action." }
            if action.kind == .rename, !FileRuleTemplate.isValid(action.value, allowsFolders: false) {
                return "Use a filename with supported placeholders and no path separators."
            }
            if action.kind == .move, !action.subfolder.isEmpty,
               !FileRuleTemplate.isValid(action.subfolder, allowsFolders: true) {
                return "Use relative subfolders with supported placeholders and no parent references."
            }
        }
        return nil
    }
}

public enum FileRuleTemplate {
    public static let tokens = ["name", "ext", "year", "month", "day", "created", "modified"]

    public static func isValid(_ template: String, allowsFolders: Bool) -> Bool {
        var literal = template
        for token in tokens { literal = literal.replacingOccurrences(of: "{\(token)}", with: "value") }
        guard !literal.contains("{"), !literal.contains("}"), !literal.contains("\0"),
              !literal.contains(":"), !literal.hasPrefix("/"), !literal.hasSuffix("/"),
              allowsFolders || !literal.contains("/") else { return false }
        return literal.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
        }
    }

    public static func render(_ template: String, file: FileMetadata) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let created = formatter.string(from: file.created)
        let parts = created.split(separator: "-")
        let values = ["name": file.url.deletingPathExtension().lastPathComponent,
                      "ext": file.url.pathExtension.lowercased(), "year": String(parts[0]),
                      "month": String(parts[1]), "day": String(parts[2]), "created": created,
                      "modified": formatter.string(from: file.modified)]
        // Parse the template once so a filename containing a token is never expanded again.
        var output = ""
        var rest = template[...]
        while let start = rest.firstIndex(of: "{"), let end = rest[start...].firstIndex(of: "}") {
            output += rest[..<start]
            let token = String(rest[rest.index(after: start)..<end])
            output += values[token] ?? String(rest[start...end])
            rest = rest[rest.index(after: end)...]
        }
        return output + rest
    }
}
