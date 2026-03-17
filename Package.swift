// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "hey-listen",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "hey-listen",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
