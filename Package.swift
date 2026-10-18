// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Glimpse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Glimpse", targets: ["Glimpse"]),
    ],
    targets: [
        .target(name: "GlimpseCore"),
        .executableTarget(
            name: "Glimpse",
            dependencies: ["GlimpseCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        // Build-time tool: turns a square artwork PNG into a macOS-style icon (scripts/build-app.sh).
        .executableTarget(name: "MakeIcon"),
        .testTarget(name: "GlimpseCoreTests", dependencies: ["GlimpseCore"]),
    ]
)
