// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flare",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Flare", targets: ["Flare"])
    ],
    targets: [
        .executableTarget(
            name: "Flare",
            path: "Sources/Flare",
            resources: [
                .copy("../../Resources/Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
