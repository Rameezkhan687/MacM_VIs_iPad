// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoleculePadCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "MoleculePadCore", targets: ["MoleculePadCore"])
    ],
    targets: [
        .target(
            name: "MoleculePadCore",
            path: "Core"
        ),
        .testTarget(
            name: "MoleculePadCoreTests",
            dependencies: ["MoleculePadCore"],
            path: "Tests"
        )
    ]
)
