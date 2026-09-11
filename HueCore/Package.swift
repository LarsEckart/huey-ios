// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HueCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HueCore", targets: ["HueCore"])
    ],
    targets: [
        .target(name: "HueCore"),
        .testTarget(name: "HueCoreTests", dependencies: ["HueCore"]),
    ]
)
