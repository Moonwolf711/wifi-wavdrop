// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WifiWavdrop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WifiWavdrop",
            targets: ["WifiWavdrop"]),
    ],
    targets: [
        .target(
            name: "WifiWavdrop"),
        .testTarget(
            name: "WifiWavdropTests",
            dependencies: ["WifiWavdrop"]),
    ]
)
