// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Macaroni",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Macaroni", targets: ["Macaroni"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/rnine/SimplyCoreAudio.git", from: "4.0.0"),
        .package(url: "https://github.com/ceeK/Solar.git", from: "3.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Macaroni",
            dependencies: [
                "KeyboardShortcuts",
                "SimplyCoreAudio",
                "Solar",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern")
            ],
            path: "Macaroni",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
