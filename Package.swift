// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeCodeUsage",
    platforms: [.macOS(.v13)],
    targets: [
        // Thin executable: sets up NSApplication and hands off to the Kit.
        .executableTarget(
            name: "ClaudeCodeUsage",
            dependencies: ["ClaudeCodeUsageKit"]
        ),
        // All app logic and UI, as a library so it can be unit-tested.
        .target(
            name: "ClaudeCodeUsageKit"
        ),
        .testTarget(
            name: "ClaudeCodeUsageKitTests",
            dependencies: ["ClaudeCodeUsageKit"]
        ),
    ]
)
