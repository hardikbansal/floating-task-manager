// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatingTaskManager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FloatingTaskManager", targets: ["FloatingTaskManager"])
    ],
    targets: [
        .executableTarget(
            name: "FloatingTaskManager",
            path: "Sources/FloatingTaskManager",
            resources: [.process("AppIcon.png")]
        )
    ]
)
