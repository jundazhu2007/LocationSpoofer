// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LocationSpoofer",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "LocationSpoofer", path: "Sources/LocationSpoofer"),
        .testTarget(name: "LocationSpooferTests", dependencies: ["LocationSpoofer"], path: "Tests/LocationSpooferTests"),
    ]
)
