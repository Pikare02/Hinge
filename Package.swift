// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hinge",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Hinge", path: "Sources/Hinge")]
)
