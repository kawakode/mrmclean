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

// MARK: Optional live scan against the real disk (MRMCLEAN_LIVE=1)

if ProcessInfo.processInfo.environment["MRMCLEAN_LIVE"] == "1" {
    h.group("Live scan")
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var snapshot: ScanSnapshot?
    Task {
        snapshot = await Scanner.run { fraction, name in
            FileHandle.standardError.write(Data("  \(Int(fraction * 100))% \(name)\n".utf8))
        }
        semaphore.signal()
    }
    semaphore.wait()
    if let snapshot {
        h.expect(snapshot.disk.totalBytes > 0, "disk capacity is reported")
        for scan in snapshot.categories {
            print("  \(scan.category.name): \(Format.bytes(scan.totalBytes))")
        }
    } else {
        h.expect(false, "live scan returned a snapshot")
    }
}

h.finish()
