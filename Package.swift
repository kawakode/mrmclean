// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MrMcLean",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MrMcLeanCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MrMcLean",
            dependencies: ["MrMcLeanCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Plain executable test runner: works with the Command Line Tools alone,
        // no XCTest or swift-testing required. Run with `swift run MrMcLeanTests`.
        .executableTarget(
            name: "MrMcLeanTests",
            dependencies: ["MrMcLeanCore"],
            path: "Tests/MrMcLeanTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
