import Foundation
import MrMcLeanCore

func runAutomationTests(_ h: Harness) async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func file(_ name: String = "Report.PDF", id: String = "one", bytes: Int64 = 2_000_000,
              tags: [String] = ["Work"]) -> FileMetadata {
        FileMetadata(url: URL(fileURLWithPath: "/fixture/\(name)"), identity: id, bytes: bytes,
                     created: now.addingTimeInterval(-40 * 86400), modified: now.addingTimeInterval(-10 * 86400),
                     tags: tags, kind: .document)
    }

    h.group("File rule conditions and config migration")
    h.expect(FileCondition(value: "pdf").matches(file(), now: now), "extension matching ignores case")
    h.expect(FileCondition(field: .name, comparison: .startsWith, value: "report").matches(file(), now: now), "filename prefix matches")
    h.expect(FileCondition(field: .tag, comparison: .equals, value: "work").matches(file(), now: now), "Finder tags match")
    h.expect(FileCondition(field: .kind, value: "document").matches(file(), now: now), "file kind matches")
    h.expect(FileCondition(field: .sizeMB, comparison: .greaterThan, value: "1").matches(file(), now: now), "size conditions use MB")
    h.expect(FileCondition(field: .createdDays, comparison: .greaterThan, value: "30").matches(file(), now: now), "creation age matches")
    h.expect(!FileCondition(field: .modifiedDays, comparison: .greaterThan, value: "30").matches(file(), now: now), "modified age differs from creation age")
    h.expect(!FileCondition(field: .openedDays, comparison: .greaterThan, value: "30").matches(file(), now: now), "missing access dates do not match")
    h.expect(!FileCondition(field: .sizeMB, comparison: .lessThan, value: "nan").matches(file(), now: now), "nonfinite numbers do not match")
    var rule = FileRule()
    rule.folder = "/fixture"
    rule.conditions.append(FileCondition(field: .tag, value: "Personal"))
    h.expect(!rule.matches(file(), now: now), "all conditions must match")
    rule.matchMode = .any
    h.expect(rule.matches(file(), now: now), "any condition can match")
    rule.conditions = []
    h.expect(!rule.matches(file(), now: now) && rule.validationError != nil, "empty conditions cannot match everything")
    rule.conditions = [FileCondition()]
    rule.actions = [FileAction(kind: .trash), FileAction()]
    h.expect(rule.validationError != nil, "Trash cannot be combined with another action")
    rule.actions = [FileAction(kind: .rename, value: "../{name}")]
    h.expect(rule.validationError != nil, "rename cannot traverse directories")
    h.expect(!FileRuleTemplate.isValid("{unknown}", allowsFolders: false), "unknown template tokens rejected")
    h.expect(!FileRuleTemplate.isValid("/outside/{name}", allowsFolders: true), "subfolders cannot be absolute")
    h.expectEqual(FileRuleTemplate.render("{name}.{ext}", file: file("{year}.PDF")), "{year}.pdf", "filename tokens are not recursively expanded")
    h.expect(!FileRuleTemplate.render("{year}/{month}/{created}", file: file()).contains("{"), "date folders expand")
    do {
        let legacy = Data("""
        {"categories":{"appLogs":{"alertEnabled":true,"thresholdPercent":7,"lastAlertBytes":99}},
         "alertsEnabled":false,"scanIntervalHours":3,"cooldownHours":72,"reAlertGrowthPercent":10,
         "showDockIcon":true,"launchMinimized":true,"hardDeleteNonCache":true,"enabledDevTools":["npm"]}
        """.utf8)
        var config = try JSONDecoder().decode(AppConfig.self, from: legacy)
        h.expect(!config.alertsEnabled && config.showDockIcon && config.launchMinimized && config.hardDeleteNonCache,
                 "legacy preferences survive new fields")
        h.expectEqual(config.category("appLogs").thresholdPercent, 7, "legacy category threshold retained")
        h.expectEqual(config.enabledDevTools, ["npm"], "legacy tool selections retained")
        h.expect(!config.automationEnabled && config.fileRules.isEmpty && !config.lowStorage.isEnabled, "new features default to opt-in")
        config.fileRules = [rule]
        config.activityAlerts = [ActivityAlertConfig()]
        config.lowStorage.threshold = 15
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        h.expect(restored == config, "new and legacy settings round-trip together")
        let empty = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        h.expect(empty == AppConfig(), "missing settings use defaults")
    } catch { h.expect(false, "config fixture: \(error)") }

    h.group("Low storage and file activity")
    var low = LowStorageConfig()
    low.isEnabled = true
    let disk = DiskInfo(totalBytes: 1_000_000_000_000, rawAvailable: 10_000_000_000, importantAvailable: 100_000_000_000)
    h.expect(low.shouldNotify(disk: disk, alertsEnabled: true, cooldownHours: 24, now: now), "low-space percentage boundary alerts")
    h.expect(!low.shouldNotify(disk: disk, alertsEnabled: false, cooldownHours: 24, now: now), "master switch suppresses low-space alerts")
    low.unit = .gigabytes
    low.threshold = 20
    h.expect(!low.shouldNotify(disk: disk, alertsEnabled: true, cooldownHours: 24, now: now), "low-space alert includes reclaimable capacity")
    low.threshold = 100
    low.lastAlertDate = now.addingTimeInterval(-60)
    h.expect(!low.shouldNotify(disk: disk, alertsEnabled: true, cooldownHours: 24, now: now), "low-space cooldown suppresses repeats")
    h.expect(low.shouldNotify(disk: disk, alertsEnabled: true, cooldownHours: 24, now: now.addingTimeInterval(86400)), "low-space alert repeats after cooldown")
    h.expect(!low.shouldNotify(disk: DiskInfo(totalBytes: 0, rawAvailable: 0, importantAvailable: 0), alertsEnabled: true, cooldownHours: 0), "unknown disk capacity stays quiet")
    var alert = ActivityAlertConfig()
    alert.isEnabled = true
    alert.folder = "/fixture"
    alert.fileCountThreshold = 2
    alert.growthEnabled = false
    var tracker = ActivityTracker()
    let baseline = ManagedFileScan(files: [file("old.log")])
    h.expect(tracker.observe(baseline, config: alert, alertsEnabled: true, cooldownHours: 24, now: now) == nil,
             "first scan establishes a baseline without alerts")
    let renamed = tracker.observe(ManagedFileScan(files: [file("renamed.log")]), config: alert, alertsEnabled: true,
                                  cooldownHours: 24, now: now.addingTimeInterval(60))
    h.expectEqual(renamed?.newFiles, 0, "renames are not counted as new files")
    let first = tracker.observe(ManagedFileScan(files: [file("renamed.log"), file("a.log", id: "two")]), config: alert,
                                alertsEnabled: true, cooldownHours: 24, now: now.addingTimeInterval(120))
    h.expect(first?.shouldNotify == false, "one new file below threshold stays quiet")
    let burstFiles = [file("renamed.log"), file("a.log", id: "two"), file("b.log", id: "three")]
    let burst = tracker.observe(ManagedFileScan(files: burstFiles), config: alert, alertsEnabled: true,
                                cooldownHours: 24, now: now.addingTimeInterval(180))
    h.expect(burst?.shouldNotify == true && burst?.newFiles == 2, "new-file bursts accumulate over the rolling window")
    alert.lastAlertDate = now.addingTimeInterval(180)
    let repeatResult = tracker.observe(ManagedFileScan(files: burstFiles), config: alert, alertsEnabled: true,
                                      cooldownHours: 24, now: now.addingTimeInterval(240))
    h.expect(repeatResult?.shouldNotify == false && repeatResult?.newFiles == 2, "recording notification preserves samples and applies cooldown")
    let expired = tracker.observe(ManagedFileScan(files: burstFiles), config: alert, alertsEnabled: true,
                                  cooldownHours: 0, now: now.addingTimeInterval(500))
    h.expect(expired?.shouldNotify == false, "old events expire from the window")
    h.expect(tracker.observe(ManagedFileScan(files: burstFiles), config: alert, alertsEnabled: true,
                            cooldownHours: 0, now: now.addingTimeInterval(2000)) == nil, "wake after a long gap resets the baseline")
    _ = tracker.observe(ManagedFileScan(issues: ["Permission denied"]), config: alert, alertsEnabled: true, cooldownHours: 0, now: now.addingTimeInterval(2010))
    h.expect(tracker.observe(baseline, config: alert, alertsEnabled: true, cooldownHours: 0, now: now.addingTimeInterval(2020)) == nil,
             "failed scans cannot cause a recovery burst")
    alert.growthEnabled = true
    alert.fileCountEnabled = false
    alert.growthMB = 1
    alert.lastAlertDate = nil
    _ = tracker.observe(baseline, config: alert, alertsEnabled: true, cooldownHours: 24, now: now)
    let growth = tracker.observe(ManagedFileScan(files: [file("old.log", bytes: 3_000_000)]), config: alert,
                                 alertsEnabled: true, cooldownHours: 24, now: now.addingTimeInterval(60))
    h.expect(growth?.shouldNotify == true && growth?.newFiles == 0, "growth of a single existing log alerts")
    alert.windowMinutes = 1
    _ = tracker.observe(baseline, config: alert, alertsEnabled: true, cooldownHours: 24, now: now)
    let minute = tracker.observe(ManagedFileScan(files: [file("old.log", bytes: 3_000_000)]), config: alert,
                                 alertsEnabled: true, cooldownHours: 24, now: now.addingTimeInterval(61))
    h.expect(minute?.shouldNotify == true, "one-minute monitoring tolerates scheduling jitter")
    h.expect(tracker.observe(baseline, config: alert, alertsEnabled: false, cooldownHours: 0, now: now) == nil, "disabled monitoring clears the baseline")

    h.group("File rules with disposable filesystem fixtures")
    do {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MrMcLean-rules-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        let trash = root.appendingPathComponent("fixture-trash")
        for folder in [source, destination, trash] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        func write(_ name: String, in folder: URL = source, aged: Bool = true) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data("fixture contents".utf8).write(to: url)
            if aged { try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: url.path) }
            return url
        }
        var rule = FileRule()
        rule.name = "Organize text"
        rule.folder = source.path
        rule.conditions = [FileCondition(value: "txt")]
        rule.actions = [FileAction(kind: .tag, value: "Work"),
                        FileAction(kind: .rename, value: "sorted-{name}.{ext}"),
                        FileAction(kind: .move, value: destination.path, subfolder: "{year}/{month}")]
        let original = try write("report.txt")
        try (original as NSURL).setResourceValue(["Existing"], forKey: .tagNamesKey)
        var journal = RuleJournal()
        var preview = RuleEngine.preview(rule: rule, journal: journal)
        h.expectEqual(preview.issues, [], "selected folder scan succeeds")
        h.expectEqual(preview.actionableCount, 1, "preview identifies one matching file")
        h.expect(fm.fileExists(atPath: original.path) && journal.receipts.isEmpty, "preview does not change files or execution history")
        var writes = 0
        let historyURL = root.appendingPathComponent("history.jsonl")
        let result = RuleEngine.execute(preview, journal: &journal, persist: { journal in
            writes += 1
            try journal.save(to: historyURL)
        })
        h.expectEqual(result.issues, [], "tag, rename and arrange actions complete")
        h.expectEqual(result.completed, 1, "one file handled by a sequence of actions")
        h.expect(writes >= 2, "history saved before and after mutations")
        let arranged = ManagedFiles.scan(folder: destination.path, recursive: true)
        h.expectEqual(arranged.files.count, 1, "arranged file is in date subfolders")
        h.expectEqual(arranged.files.first?.url.lastPathComponent, "sorted-report.txt", "rename uses the original filename")
        h.expectEqual(Set(arranged.files.first?.tags ?? []), ["Existing", "Work"], "adding a Finder tag preserves existing tags")
        h.expect(!fm.fileExists(atPath: original.path), "move removes the source")
        h.expectEqual(journal.receipts.first?.status, .completed, "completed activity is recorded")
        let saved = try RuleJournal.load(from: historyURL)
        h.expectEqual(saved.receipts.count, 1, "append-only history folds reservation and completion into one receipt")
        h.expectEqual(saved.receipts.first?.status, .completed, "history is durable on disk")
        h.expectEqual(saved.handledIdentities(for: rule), journal.handledIdentities(for: rule), "durable history retains processed identities")
        let damagedURL = root.appendingPathComponent("damaged.jsonl")
        try Data("{partial".utf8).write(to: damagedURL)
        h.expectThrows("partial history writes stop automation on restart") { _ = try RuleJournal.load(from: damagedURL) }

        // Rename in place, then re-load history to prove restart idempotence.
        rule.actions = [FileAction(kind: .rename, value: "prefix-{name}.{ext}")]
        let once = try write("once.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        _ = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        journal = try JSONDecoder().decode(RuleJournal.self, from: JSONEncoder().encode(journal))
        let again = RuleEngine.preview(rule: rule, journal: journal)
        h.expectEqual(again.alreadyHandled, 1, "saved history prevents repeating a prefix rename")
        h.expectEqual(again.actionableCount, 0, "previously renamed file needs no action after restart")
        h.expect(!fm.fileExists(atPath: once.path), "in-place rename ran once")
        let revision = rule.revision
        rule.isEnabled.toggle()
        rule.name = "Renamed rule"
        h.expect(rule.revision == revision, "toggling or renaming a rule does not rerun it")

        rule.conditions = [FileCondition(field: .name, value: "collision.txt")]
        rule.actions = [FileAction(kind: .rename, value: "occupied.txt")]
        let collision = try write("collision.txt")
        let occupied = try write("occupied.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        h.expectEqual(preview.actionableCount, 0, "existing destination is blocked during preview")
        _ = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        h.expect(fm.fileExists(atPath: collision.path) && fm.fileExists(atPath: occupied.path), "collision keeps both files intact")

        rule.actions = [FileAction(kind: .rename, value: "late.txt")]
        preview = RuleEngine.preview(rule: rule, journal: journal)
        _ = try write("late.txt")
        let late = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        h.expect(late.completed == 0 && !late.issues.isEmpty, "destination created after preview is not overwritten")
        rule.actions = [FileAction(kind: .rename, value: "changed.txt")]
        preview = RuleEngine.preview(rule: rule, journal: journal)
        try Data("contents changed after preview".utf8).write(to: collision)
        let stale = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        h.expect(stale.completed == 0 && !stale.issues.isEmpty, "changed source is skipped at execution")

        rule.conditions = [FileCondition(field: .name, value: "reserve.txt")]
        rule.actions = [FileAction(kind: .rename, value: "reserved.txt")]
        let reserve = try write("reserve.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        let noHistory = RuleEngine.execute(preview, journal: &journal, persist: { _ in throw FileManagementError("Disk full") })
        h.expect(noHistory.completed == 0 && noHistory.historyFailure != nil && fm.fileExists(atPath: reserve.path), "failed history write prevents file changes and pauses the run")

        rule.conditions = [FileCondition(field: .name, value: "trash.txt")]
        rule.actions = [FileAction(kind: .trash)]
        let doomed = try write("trash.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        let trashed = RuleEngine.execute(preview, journal: &journal, persist: { _ in }, trash: { url in
            try fm.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        })
        h.expectEqual(trashed.completed, 1, "Trash action invokes the recoverable operation")
        h.expect(!fm.fileExists(atPath: doomed.path) && fm.fileExists(atPath: trash.appendingPathComponent("trash.txt").path), "trashed fixture remains recoverable")

        rule.conditions = [FileCondition(field: .name, value: "failed.txt")]
        _ = try write("failed.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        let failed = RuleEngine.execute(preview, journal: &journal, persist: { _ in }, trash: { _ in throw FileManagementError("Trash unavailable") })
        h.expect(failed.completed == 0 && journal.receipts.last?.status == .failed, "failed action appears in history")
        h.expectEqual(RuleEngine.preview(rule: rule, journal: journal).alreadyHandled, 1, "failed actions are not blindly retried")

        let outside = try write("outside.txt", in: destination)
        try fm.createSymbolicLink(at: source.appendingPathComponent("escape.txt"), withDestinationURL: outside)
        let package = source.appendingPathComponent("Example.app")
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        _ = try write("inside.txt", in: package)
        _ = try write(".hidden.txt")
        let nested = source.appendingPathComponent("nested")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try write("nested.txt", in: nested)
        try fm.linkItem(at: reserve, to: source.appendingPathComponent("hardlink.txt"))
        let flat = ManagedFiles.scan(folder: source.path, recursive: false)
        let recursive = ManagedFiles.scan(folder: source.path, recursive: true)
        h.expectEqual(recursive.issues, [], "skipping links does not make the scan fail")
        h.expect(!recursive.files.contains { ["escape.txt", "inside.txt", ".hidden.txt", "hardlink.txt", "reserve.txt"].contains($0.url.lastPathComponent) },
                 "symlinks, hard links, hidden files and package contents are excluded")
        h.expect(!flat.files.contains { $0.url.lastPathComponent == "nested.txt" }
                 && recursive.files.contains { $0.url.lastPathComponent == "nested.txt" }, "subfolder recursion is configurable")
        h.expect(!ManagedFiles.scan(folder: source.path, recursive: true, limit: 1).issues.isEmpty, "scan limits produce a visible partial result")
        h.expect(!ManagedFiles.scan(folder: root.appendingPathComponent("missing").path, recursive: true).issues.isEmpty, "missing folder is an error, not an empty success")
        h.expectThrows("file validation rejects a symbolic-link escape") { try ManagedFolder.validateFile(source.appendingPathComponent("escape.txt"), in: source) }
        h.expectThrows("system folders cannot be a rule scope") { _ = try ManagedFolder.resolve("/System") }
        h.expectThrows("home-wide rules are rejected") { _ = try ManagedFolder.resolve(NSHomeDirectory()) }
        h.expectThrows("Library databases cannot be a rule scope") { _ = try ManagedFolder.resolve(NSHomeDirectory() + "/Library") }
        h.expectThrows("app bundles cannot be selected as rule folders") { _ = try ManagedFolder.resolve(package.path) }

        rule.conditions = [FileCondition(field: .name, value: "fresh.txt")]
        rule.actions = [FileAction(kind: .tag)]
        _ = try write("fresh.txt", aged: false)
        h.expectEqual(RuleEngine.preview(rule: rule, journal: journal).settling, 1, "actively modified files wait before automation")

        rule.conditions = [FileCondition(field: .name, value: "atomic.txt")]
        rule.actions = [FileAction(kind: .move, value: destination.path, subfolder: "new-folder"),
                        FileAction(kind: .rename, value: "after-move.txt")]
        _ = try write("atomic.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        let ordered = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        h.expect(ordered.completed == 1 && ordered.issues.isEmpty, "move then rename also respects action order")
        h.expect(fm.fileExists(atPath: destination.appendingPathComponent("new-folder/after-move.txt").path), "move then rename reaches the expected file")

        rule.conditions = [FileCondition(field: .name, value: "redirect.txt")]
        rule.actions = [FileAction(kind: .move, value: destination.path, subfolder: "redirect")]
        let retained = try write("redirect.txt")
        preview = RuleEngine.preview(rule: rule, journal: journal)
        try fm.createSymbolicLink(at: destination.appendingPathComponent("redirect"), withDestinationURL: trash)
        let redirected = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        h.expect(redirected.completed == 0 && !redirected.issues.isEmpty && fm.fileExists(atPath: retained.path),
                 "destination symlink introduced after preview is rejected")

        rule.actions = [FileAction(kind: .tag)]
        preview = RuleEngine.preview(rule: rule, journal: journal)
        preview.issues = ["Incomplete scan"]
        let partial = RuleEngine.execute(preview, journal: &journal, persist: { _ in })
        h.expect(partial.completed == 0 && !partial.issues.isEmpty, "a partial scan cannot execute otherwise valid matches")

        _ = try write("one.cancel")
        _ = try write("two.cancel")
        rule.conditions = [FileCondition(value: "cancel")]
        rule.actions = [FileAction(kind: .rename, value: "done-{name}.{ext}")]
        let cancelPreview = RuleEngine.preview(rule: rule, journal: RuleJournal())
        let cancelled = await Task.detached {
            var history = RuleJournal()
            return RuleEngine.execute(cancelPreview, journal: &history, persist: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }.value
        h.expectEqual(cancelled.completed, 1, "pausing a batch finishes the reserved file and stops before the next")
        h.expect(fm.fileExists(atPath: source.appendingPathComponent("two.cancel").path), "paused batch leaves the next file untouched")
    } catch { h.expect(false, "file rule fixture: \(error)") }
}
