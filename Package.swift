// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MrMcLean",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MrMcLeanCore"),
        .executableTarget(
            name: "MrMcLean",
            dependencies: ["MrMcLeanCore"]
        ),
        // Plain executable test runner: works with the Command Line Tools alone,
        // no XCTest or swift-testing required. Run with `swift run MrMcLeanTests`.
        .executableTarget(
            name: "MrMcLeanTests",
            dependencies: ["MrMcLeanCore"],
            path: "Tests/MrMcLeanTests"
        ),
    ]
)
