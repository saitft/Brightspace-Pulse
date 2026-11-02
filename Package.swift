// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BrightspaceSync",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BrightspaceSync", targets: ["BrightspaceSync"])
    ],
    targets: [
        .executableTarget(
            name: "BrightspaceSync",
            path: "Sources/BrightspaceSync",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CryptoKit")
            ]
        )
    ]
)
