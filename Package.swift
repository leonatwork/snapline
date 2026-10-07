// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Snapline",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SnaplineCore"),
        .executableTarget(name: "Snapline", dependencies: ["SnaplineCore"]),
        .testTarget(name: "SnaplineCoreTests", dependencies: ["SnaplineCore"]),
    ]
)
