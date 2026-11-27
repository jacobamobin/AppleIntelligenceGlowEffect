// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicGlow",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "MusicGlow", targets: ["MusicGlow"])],
    targets: [
        .target(name: "GlowCore"),
        .executableTarget(name: "MusicGlow", dependencies: ["GlowCore"], resources: [.copy("Glow.metal")]),
        .testTarget(name: "GlowCoreTests", dependencies: ["GlowCore"])
    ]
)
