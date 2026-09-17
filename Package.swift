// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmpRunner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AmpRunner", targets: ["AmpRunner"]),
        .executable(name: "AmpRunnerService", targets: ["AmpRunnerService"])
    ],
    targets: [
        .target(name: "RunnerCore"),
        .executableTarget(name: "AmpRunner", dependencies: ["RunnerCore"]),
        .executableTarget(name: "AmpRunnerService", dependencies: ["RunnerCore"]),
        .testTarget(name: "RunnerCoreTests", dependencies: ["RunnerCore"])
    ]
)
