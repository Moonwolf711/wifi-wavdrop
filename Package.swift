// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WaveDrop",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "WaveDrop",
            targets: ["WaveDrop"]),
        .library(
            name: "WaveDropShareExtension",
            targets: ["WaveDropShareExtension"]),
    ],
    dependencies: [
        // AudioKit for advanced audio processing
        .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.0"),
        // ID3TagEditor for reading/writing ID3 tags
        .package(url: "https://github.com/chicio/ID3TagEditor", from: "4.0.0"),
        // Alamofire for networking with ESP32-S3
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.0"),
        // Swift Collections for additional collection types
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "WaveDrop",
            dependencies: [
                "AudioKit",
                "ID3TagEditor",
                "Alamofire",
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "Sources/WaveDrop"),
        .target(
            name: "WaveDropShareExtension",
            dependencies: [
                "WaveDrop"
            ],
            path: "Sources/WaveDropShareExtension"),
        .testTarget(
            name: "WaveDropTests",
            dependencies: ["WaveDrop"],
            path: "Tests/WaveDropTests"),
    ]
)
