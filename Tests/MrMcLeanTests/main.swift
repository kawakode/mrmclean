import Foundation
import MrMcLeanCore

let h = Harness()
let home = NSHomeDirectory()

// MARK: SafePath

h.group("SafePath")

h.expectNoThrow("accepts a cache child") {
    try SafePath.validate("\(home)/Library/Caches/com.example.app")
}
h.expectNoThrow("accepts a container cache path") {
    try SafePath.validate("\(home)/Library/Containers/com.example.app/Data/Library/Caches/Stuff")
}
h.expectNoThrow("accepts DerivedData") {
    try SafePath.validate("\(home)/Library/Developer/Xcode/DerivedData/App-abcdef")
}
h.expectThrows("rejects the cache root itself") {
    try SafePath.validate("\(home)/Library/Caches")
}
h.expectThrows("rejects the home directory") {
    try SafePath.validate(home)
}
h.expectThrows("rejects /") {
    try SafePath.validate("/")
}
h.expectThrows("rejects /System") {
    try SafePath.validate("/System/Library/Caches/whatever")
}
h.expectThrows("rejects Documents") {
    try SafePath.validate("\(home)/Documents/taxes.pdf")
}
h.expectThrows("rejects MobileSync backups") {
    try SafePath.validate("\(home)/Library/Application Support/MobileSync/Backup/abc")
}
h.expectThrows("rejects parent-reference traversal") {
    try SafePath.validate("\(home)/Library/Caches/../../.ssh")
}
h.expectThrows("rejects a non-cache container path") {
    try SafePath.validate("\(home)/Library/Containers/com.example.app/Data/Documents/file")
}
h.expectThrows("rejects a non-allowlisted Developer path") {
    try SafePath.validate("\(home)/Library/Developer/CoreSimulator/Devices/UUID/data")
}
h.expectThrows("rejects an empty path") {
    try SafePath.validate("   ")
}

// MARK: AlertLogic

h.group("AlertLogic")

let disk: Int64 = 1_000_000_000_000

func globalConfig() -> AppConfig {
    var config = AppConfig()
    config.alertsEnabled = true
    config.cooldownHours = 24
    config.reAlertGrowthPercent = 5
    return config
}

func categoryConfig(threshold: Double = 10, enabled: Bool = true) -> CategoryConfig {
    var category = CategoryConfig()
    category.alertEnabled = enabled
    category.thresholdPercent = threshold
    return category
}

h.expect(
    AlertLogic.evaluate(sizeBytes: disk / 20, diskBytes: disk,
                        category: categoryConfig(), global: globalConfig()).shouldNotify == false,
    "below threshold stays quiet"
)
h.expect(
    AlertLogic.evaluate(sizeBytes: disk / 5, diskBytes: disk,
                        category: categoryConfig(), global: globalConfig()).shouldNotify,
    "above threshold, first time, notifies"
)
h.expect(
    AlertLogic.evaluate(sizeBytes: disk / 2, diskBytes: disk,
                        category: categoryConfig(enabled: false), global: globalConfig()).shouldNotify == false,
    "disabled category stays quiet"
)
do {
    var global = globalConfig()
    global.alertsEnabled = false
    h.expect(
        AlertLogic.evaluate(sizeBytes: disk / 2, diskBytes: disk,
                            category: categoryConfig(), global: global).shouldNotify == false,
        "master switch off stays quiet"
    )
}
do {
    var category = categoryConfig()
    category.lastAlertDate = Date().addingTimeInterval(-3600)
    category.lastAlertBytes = disk / 5
    h.expect(
        AlertLogic.evaluate(sizeBytes: disk / 5, diskBytes: disk,
                            category: category, global: globalConfig()).shouldNotify == false,
        "within cooldown, no growth, stays quiet"
    )
    h.expect(
        AlertLogic.evaluate(sizeBytes: disk / 3, diskBytes: disk,
                            category: category, global: globalConfig()).shouldNotify,
        "within cooldown, large growth, notifies"
    )
}
do {
    var category = categoryConfig()
    category.lastAlertDate = Date().addingTimeInterval(-48 * 3600)
    category.lastAlertBytes = disk / 5
    h.expect(
        AlertLogic.evaluate(sizeBytes: disk / 5, diskBytes: disk,
                            category: category, global: globalConfig()).shouldNotify,
        "past cooldown notifies again"
    )
}
h.expect(
    abs(AlertLogic.evaluate(sizeBytes: disk / 4, diskBytes: disk,
                            category: categoryConfig(), global: globalConfig()).fraction - 0.25) < 0.0001,
    "fraction is reported"
)

// MARK: Parsing

h.group("Parsing")

do {
    let output = "1024\t/root/a\n2048\t/root/b\n4096\t/root"
    let result = DuParse.breakdown(output, root: "/root")
    h.expectEqual(result.total, 4096 * 1024, "du breakdown total")
    h.expectEqual(result.children.count, 2, "du breakdown child count")
    h.expectEqual(result.children.first?.path ?? "", "/root/b", "du children sorted by size")
}
do {
    let result = DuParse.breakdown("100\t/root/a\n200\t/root/b\n", root: "/root")
    h.expectEqual(result.total, 300 * 1024, "du breakdown falls back to summing children")
}
h.expectEqual(DuParse.lines("junk\n512\t/x\n\n").count, 1, "du line parser skips garbage")
h.expectEqual(SnapshotTool.stamp(from: "com.apple.TimeMachine.2024-01-15-123456.local") ?? "",
              "2024-01-15-123456", "snapshot stamp extraction")
h.expect(SnapshotTool.stamp(from: "something.else") == nil, "snapshot stamp rejects other names")
h.expect(SnapshotTool.date(from: "2024-01-15-123456") != nil, "snapshot date parses")
h.expectEqual(Format.bytes(-5), Format.bytes(0), "negative bytes clamp to zero")
h.expectEqual(Format.percent(1.5), "100%", "percent clamps high")
h.expectEqual(Format.percent(-0.2), "0%", "percent clamps low")
h.expectEqual(Format.percent(0.256, digits: 1), "25.6%", "percent rounds")

// MARK: Full Disk Access

h.group("Access")

h.expectEqual(ProbeIssues.classify(stderr: "", timedOut: false), [], "a clean du run has no issues")
h.expect(
    ProbeIssues.classify(stderr: "du: /x: Operation not permitted", timedOut: false)
        .contains(.permissionDenied),
    "EPERM stderr is flagged as permissionDenied"
)
h.expect(
    ProbeIssues.classify(stderr: "du: a/b: Permission denied", timedOut: false)
        .contains(.permissionDenied),
    "EACCES stderr is flagged as permissionDenied"
)
h.expect(
    ProbeIssues.classify(stderr: "", timedOut: true).contains(.timedOut),
    "a killed du run is flagged as timedOut"
)
h.expect(URL(string: FullDiskAccess.settingsURLString) != nil, "the settings deep link parses")
h.expect(
    [.granted, .denied, .unknown].contains(FullDiskAccess.check()),
    "FullDiskAccess.check returns a known status without crashing"
)
h.expect(
    FullDiskAccessStatus(rawValue: "denied") == .denied
        && FullDiskAccessStatus(rawValue: "granted") == .granted
        && FullDiskAccessStatus(rawValue: "nope") == nil,
    "FullDiskAccessStatus round-trips its raw value (used by the MRMCLEAN_FORCE_FDA test hook)"
)

do {
    let disk = DiskInfo(totalBytes: 100, rawAvailable: 10, importantAvailable: 20)
    let clean = ScanSnapshot(disk: disk, categories: [], date: Date(), fullDiskAccess: .granted)
    h.expect(clean.sizesUnderReported == false, "granted access with no issues is not under-reported")

    let denied = ScanSnapshot(disk: disk, categories: [], date: Date(), fullDiskAccess: .denied)
    h.expect(denied.sizesUnderReported, "denied access is under-reported")

    let stalled = CategoryScan(category: Catalog.userCaches, totalBytes: 0,
                               entries: [], itemCount: 0, issues: .timedOut)
    let partial = ScanSnapshot(disk: disk, categories: [stalled], date: Date(), fullDiskAccess: .granted)
    h.expect(partial.scanIssues.contains(.timedOut), "aggregate scanIssues includes a category's issues")
    h.expect(partial.sizesUnderReported, "a timed-out category makes the snapshot under-reported")

    let adminOnly = CategoryScan(category: Catalog.systemCaches, totalBytes: 0,
                                 entries: [], itemCount: 0, issues: .permissionDenied)
    let adminSnapshot = ScanSnapshot(disk: disk, categories: [adminOnly], date: Date(), fullDiskAccess: .granted)
    h.expect(
        adminSnapshot.sizesUnderReported == false,
        "a denied admin-only category does not count as under-reported (root paths need the admin step)"
    )
}

// MARK: Full clean

h.group("FullClean")

do {
    let steps = FullClean.plan(includeSystem: false)
    h.expectEqual(steps.map(\.id), ["userCaches", "appLogs", "developer", "trash"],
                  "safe plan is caches, logs, developer, trash in order")
}
do {
    let steps = FullClean.plan(includeSystem: true, includeSnapshots: true, devToolIDs: ["brew", "npm"])
    h.expectEqual(steps.first?.id ?? "", "userCaches", "plan starts with user caches")
    h.expectEqual(steps.last?.id ?? "", "system", "system step is last when included")
    h.expect(steps.contains { $0.id == "devTools" }, "dev tools step present when ids are given")
    if case .system(let snapshots)? = steps.last?.work {
        h.expect(snapshots, "system step carries the includeSnapshots flag")
    } else {
        h.expect(false, "last step is a system step")
    }
}
do {
    let steps = FullClean.plan(includeSystem: false, devToolIDs: [])
    h.expect(!steps.contains { $0.id == "devTools" }, "no dev tools step without ids")
    h.expect(!steps.contains { $0.id == "system" }, "no system step when not included")
}
do {
    let disk = DiskInfo(totalBytes: 1000, rawAvailable: 100, importantAvailable: 100)
    var report = FullCleanReport(
        phases: [
            FullCleanPhase(id: "a", title: "A", symbol: "x"),
            FullCleanPhase(id: "b", title: "B", symbol: "y"),
        ],
        startedAt: Date(timeIntervalSinceNow: -12),
        diskBefore: disk
    )
    h.expect(report.progress == 0, "fresh report has zero progress")
    h.expect(!report.isComplete, "fresh report is not complete")

    report.update("a") { $0.status = .done; $0.freedBytes = 500; $0.removedCount = 3 }
    report.update("b") { $0.status = .failed; $0.skippedCount = 1; $0.note = "nope" }
    h.expectEqual(report.totalFreedBytes, 500, "report sums freed bytes")
    h.expectEqual(report.totalRemoved, 3, "report sums removed count")
    h.expectEqual(report.totalSkipped, 1, "report sums skipped count")
    h.expect(report.anyFailed, "a failed phase is reflected")
    h.expect(report.progress == 1.0, "both phases resolved means progress is complete")

    report.diskAfter = DiskInfo(totalBytes: 1000, rawAvailable: 400, importantAvailable: 400)
    h.expectEqual(report.diskFreedBytes ?? -1, 300, "disk freed is measured from the volume delta")
    h.expectEqual(report.headlineFreedBytes, 300, "headline prefers the measured volume delta")

    report.finishedAt = Date()
    h.expect(report.isComplete, "a finished report is complete")
}
do {
    // A measured zero must not be replaced by an optimistic estimate.
    let disk = DiskInfo(totalBytes: 1000, rawAvailable: 100, importantAvailable: 100)
    var report = FullCleanReport(phases: [FullCleanPhase(id: "a", title: "A", symbol: "x")],
                                 diskBefore: disk)
    report.update("a") { $0.status = .done; $0.freedBytes = 250 }
    report.diskAfter = disk
    h.expectEqual(report.headlineFreedBytes, 0, "headline preserves a measured zero volume gain")
}


// MARK: Regression checks

h.group("Cleanup regressions")
h.expect(ProbeIssues.classify(stderr: "unknown failure", timedOut: false, exitCode: 1).contains(.failed),
         "unrecognized probe failures are flagged")
h.expectEqual(Format.relativeDate(Date()), "just now", "fresh scans do not read in zero seconds")

h.expectNoThrow("Mail Downloads children are cleanable") {
    try SafePath.validate("\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/attachment.pdf")
}
h.expectThrows("Mail Downloads root is retained") {
    try SafePath.validate("\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
}
h.expectThrows("a cache-like container name is rejected") {
    try SafePath.validate("\(home)/Library/Containers/com.example.app/Data/Library/CachesBackup/important")
}
h.expectThrows("a nested fake cache subtree is rejected") {
    try SafePath.validate("\(home)/Library/Containers/com.example.app/Documents/Data/Library/Caches/file")
}
h.expectThrows("a developer prefix lookalike is rejected") {
    try SafePath.validate("\(home)/Library/Developer/Xcode/ArchivesPersonal/file")
}
h.expectThrows("developer cache root is retained") {
    try SafePath.validate("\(home)/Library/Developer/Xcode/DerivedData")
}
h.expect(SnapshotTool.stamp(from: "com.apple.TimeMachine.2024-01-15-123456;whoami.local") == nil,
         "snapshot stamps reject shell metacharacters")

do {
    let entries = [SizedEntry(path: "/cache/tool/child", bytes: 40),
                   SizedEntry(path: "/cache/tool", bytes: 100),
                   SizedEntry(path: "/cache/tool", bytes: 100),
                   SizedEntry(path: "/cache/tool-other", bytes: 20)]
    let unique = Cleaner.uniqueItems(entries)
    h.expectEqual(unique.count, 2, "nested and duplicate entries counted only once")
    h.expectEqual(unique.reduce(0) { $0 + $1.bytes }, 120, "sibling prefixes remain distinct")
    let snapshot = ScanSnapshot(disk: DiskInfo(totalBytes: 1000, rawAvailable: 100, importantAvailable: 100),
        categories: [
            CategoryScan(category: Catalog.userCaches, totalBytes: 120, entries: unique, itemCount: 2),
            CategoryScan(category: Catalog.developer, totalBytes: 500,
                         entries: [SizedEntry(path: "/archives", bytes: 500)], itemCount: 1),
            CategoryScan(category: Catalog.trash, totalBytes: 200,
                         entries: [SizedEntry(path: "/trash", bytes: 200)], itemCount: 1)
        ], date: Date())
    h.expectEqual(snapshot.quickCleanBytes, 120, "quick cleanup excludes developer archives and Trash")
    var report = FullCleanReport(phases: [FullCleanPhase(id: "partial", title: "Partial", symbol: "x")],
                                 diskBefore: snapshot.disk)
    report.update("partial") { $0.status = .done; $0.skippedCount = 2 }
    h.expect(report.anyFailed, "skipped deletions prevent an all-clean report")
}

h.group("Filesystem and command regressions")

do {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MrMcLean-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let looseFile = root.appendingPathComponent("loose.log")
    let newlineFile = root.appendingPathComponent("line\nbreak.dat")
    try Data(repeating: 65, count: 8192).write(to: looseFile)
    try Data(repeating: 66, count: 16384).write(to: newlineFile)
    let trash = root.appendingPathComponent(".Trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    try Data(repeating: 67, count: 32768).write(to: trash.appendingPathComponent("excluded.dat"))

    let parsed = await SizeProbe.breakdown(root.path)
    h.expect(parsed.children.contains { $0.path == looseFile.resolvingSymlinksInPath().path }, "loose files appear in cleanup breakdown")
    h.expect(parsed.children.contains { $0.path == newlineFile.resolvingSymlinksInPath().path }, "newline file appears in cleanup breakdown")


    let cacheFixture = URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/MrMcLean-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: cacheFixture, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cacheFixture) }
    let link = cacheFixture.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    let rejected = Cleaner.execute(items: [SizedEntry(path: link.appendingPathComponent("loose.log").path, bytes: 8192)], mode: .hardDelete)
    h.expectEqual(rejected.failed.count, 1, "cleanup rejects symlink escape from an allowed cache")
    h.expect(FileManager.default.fileExists(atPath: looseFile.path), "rejected cleanup preserves target data")
    let owned = cacheFixture.appendingPathComponent("owned-test-file")
    try Data(repeating: 42, count: 4096).write(to: owned)
    let duplicate = SizedEntry(path: owned.path, bytes: 4096)
    let cleaned = Cleaner.execute(items: [duplicate, duplicate], mode: .hardDelete)
    h.expectEqual(cleaned.removed.count, 1, "real duplicate deletion removes one fixture file")
    h.expectEqual(cleaned.freedBytes, 4096, "real duplicate deletion counts space once")
    h.expect(!FileManager.default.fileExists(atPath: owned.path), "cleaner removed the fixture file")

    let found = await LargeFiles.scan(minimumBytes: 1024, limit: 1, root: root.path)
    h.expectEqual(found.totalFound, 2, "large-file scan excludes Trash")
    h.expectEqual(found.entries.count, 1, "large-file limit retains total match count")
    h.expectEqual(found.totalBytes, 24576, "large-file totals include matches beyond the display limit")
    var summary = ScanSnapshot(disk: DiskInfo(totalBytes: 100000, rawAvailable: 1, importantAvailable: 1), categories: [], date: Date())
    summary.recordLargeFiles(found)
    summary.recordLargeFiles(found)
    h.expectEqual(summary.categories.count, 1, "refreshing large files replaces the previous summary")
    h.expectEqual(summary.category("largeFiles")?.totalBytes, found.totalBytes, "large-file results reach the sidebar and overview summary")
    h.expectEqual(found.entries.first?.path, newlineFile.path, "newline filename survives large-file scan")
    h.expect(!found.isPartial, "successful large-file scan is complete")
    let empty = await LargeFiles.scan(minimumBytes: 100_000, root: root.path)
    h.expect(empty.entries.isEmpty && !empty.isPartial, "empty scan is a successful completed result")
    let missing = await LargeFiles.scan(root: root.appendingPathComponent("missing").path)
    h.expect(missing.isPartial && missing.failure != nil, "failed scan is distinguishable from empty results")

    let failed = await Shell.result("/bin/sh", ["-c", "printf 'tool failed' >&2; exit 7"])
    h.expect(!failed.succeeded, "nonzero tool exit is not success")
    h.expectEqual(failed.failureDescription, "tool failed", "tool error details retained")
    let timedOut = await Shell.result("/bin/sleep", ["5"], timeout: 0.05)
    h.expect(timedOut.timedOut && !timedOut.succeeded, "timed-out command is a failure")
    let script = await AdminCleaner.systemCleanScript(includeSnapshots: false)
    h.expect(!script.contains("exit 0") && script.contains("exit $status"), "administrator script propagates failures")
    h.expect(!script.contains("2>/dev/null"), "administrator script preserves error details")
    let syntax = await Shell.result("/bin/sh", ["-n", "-c", script])
    h.expect(syntax.succeeded, "generated administrator script passes shell syntax check without executing")
} catch {
    h.expect(false, "filesystem regression fixture: \(error)")
}

// MARK: Optional live scan against the real disk (MRMCLEAN_LIVE=1)

if ProcessInfo.processInfo.environment["MRMCLEAN_LIVE"] == "1" {
    h.group("Live scan")
    let snapshot = await Scanner.run { fraction, name in
        FileHandle.standardError.write(Data("  \(Int(fraction * 100))% \(name)\n".utf8))
    }
    do {
        h.expect(snapshot.disk.totalBytes > 0, "disk capacity is reported")
        print("  Full Disk Access: \(snapshot.fullDiskAccess.rawValue)")
        for scan in snapshot.categories {
            var notes: [String] = []
            if scan.issues.contains(.permissionDenied) { notes.append("denied") }
            if scan.issues.contains(.timedOut) { notes.append("timed-out") }
            let flags = notes.isEmpty ? "" : "  [\(notes.joined(separator: ", "))]"
            print("  \(scan.category.name): \(Format.bytes(scan.totalBytes))\(flags)")
        }
        if snapshot.sizesUnderReported {
            print("  -> sizes are under-reported")
        }
    }
}

h.finish()
