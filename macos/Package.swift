// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Check if push notifications feature is enabled via marker file from Rust build
let enablePushNotifications = FileManager.default.fileExists(
  atPath: URL(fileURLWithPath: #file).deletingLastPathComponent()
    .appendingPathComponent(".push-notifications-enabled").path
)

var swiftSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-import-objc-header", "\(Context.packageDirectory)/Sources/bridging-header.h",
        "-disable-bridging-pch"
    ])
]
if enablePushNotifications {
  swiftSettings.append(.define("ENABLE_PUSH_NOTIFICATIONS"))
}

let package = Package(
    name: "tauri-plugin-notifications",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "tauri-plugin-notifications",
            type: .static,
            targets: ["tauri-plugin-notifications"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.20.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "tauri-plugin-notifications",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk")
            ],
            path: "Sources",
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "PluginTests",
            dependencies: ["tauri-plugin-notifications"],
            swiftSettings: swiftSettings
        ),
    ]
)
