// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "Gatewire",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "Gatewire", targets: ["Gatewire"]),
        .library(name: "GatewireTesting", targets: ["GatewireTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.11.0")),
    ],
    targets: [
        .target(
            name: "Gatewire",
            dependencies: ["Alamofire"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "GatewireTesting",
            dependencies: ["Gatewire"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "GatewireTests",
            dependencies: ["Gatewire", "GatewireTesting", "Alamofire"],
            swiftSettings: swiftSettings
        ),
    ]
)
