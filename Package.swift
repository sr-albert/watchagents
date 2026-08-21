// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeMonitor",
            path: "Sources/ClaudeMonitor",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "ClaudeMonitorTests",
            dependencies: ["ClaudeMonitor"],
            path: "Tests/ClaudeMonitorTests"
        )
    ]
)
