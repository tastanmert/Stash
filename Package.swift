// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "StashCore"),
        .executableTarget(
            name: "Stash",
            dependencies: ["StashCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "StashCoreTests", dependencies: ["StashCore"]),
    ]
)
