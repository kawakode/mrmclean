import Foundation

public enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter
    }()

    public static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, value))
    }

    /// `fraction` is 0...1.
    public static func percent(_ fraction: Double, digits: Int = 0) -> String {
        let clamped = min(max(fraction, 0), 1)
        return String(format: "%.\(digits)f%%", clamped * 100)
    }

    public static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
