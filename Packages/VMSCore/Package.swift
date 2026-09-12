// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VMSCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VMSCore",
            targets: ["VMSCore"]
        )
    ],
    targets: [
        .target(
            name: "VMSCore"
        ),
        .testTarget(
            name: "VMSCoreTests",
            dependencies: ["VMSCore"]
        )
    ]
)
