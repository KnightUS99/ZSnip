// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZSnip",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "ZSnip",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ZSnip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
