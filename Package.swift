// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BrightspaceSync",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BrightspaceSync", targets: ["BrightspaceSync"]),
        .executable(name: "BrightspaceSyncTests", targets: ["BrightspaceSyncTests"]),
        .library(name: "BrightspaceSyncCore", targets: ["BrightspaceSyncCore"])
    ],
    targets: [
        .target(
            name: "BrightspaceSyncCore",
            path: "Sources/BrightspaceSyncCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CryptoKit")
            ]
        ),
        .executableTarget(
            name: "BrightspaceSync",
            dependencies: [
                "BrightspaceSyncCore"
            ],
            path: "Sources/BrightspaceSync",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "BrightspaceSyncTests",
            dependencies: [
                "BrightspaceSyncCore"
            ],
            path: "Tests/BrightspaceSyncTests"
        )
    ]
)
