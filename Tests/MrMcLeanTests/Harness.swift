import Foundation

/// Tiny assertion harness. No XCTest, no swift-testing, so it runs anywhere the
/// toolchain runs.
final class Harness {
    private(set) var passed = 0
    private(set) var failed = 0
    private var currentGroup = ""

    func group(_ name: String) {
        currentGroup = name
        print("\n\(name)")
    }

    func expect(_ condition: Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
        if condition {
            passed += 1
            print("  ok   \(label)")
        } else {
            failed += 1
            print("  FAIL \(label)  (\(file):\(line))")
        }
    }

    func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ label: String,
                                   file: StaticString = #file, line: UInt = #line) {
        expect(lhs == rhs, "\(label)  [\(lhs) == \(rhs)]", file: file, line: line)
    }

    func expectThrows(_ label: String, file: StaticString = #file, line: UInt = #line,
                      _ body: () throws -> Void) {
        do {
            try body()
            expect(false, "\(label)  (expected a throw)", file: file, line: line)
        } catch {
            expect(true, label, file: file, line: line)
        }
    }

    func expectNoThrow(_ label: String, file: StaticString = #file, line: UInt = #line,
                       _ body: () throws -> Void) {
        do {
            try body()
            expect(true, label, file: file, line: line)
        } catch {
            expect(false, "\(label)  (threw \(error))", file: file, line: line)
        }
    }

    func finish() -> Never {
        print("\n\(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
