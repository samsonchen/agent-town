// swift-tools-version: 6.0
// agent-town macOS app. Open this folder in Xcode, or build with `swift build`.
import PackageDescription

let package = Package(
    name: "AgentTown",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AgentTown", targets: ["AgentTown"]),
    ],
    targets: [
        // Protocol decoding, building state, timing and sound rules. No UI, no RealityKit.
        .target(name: "TownCore"),
        .executableTarget(
            name: "AgentTown",
            dependencies: ["TownCore"],
            resources: [
                .copy("Resources/models"), // symlink to assets/models
                .copy("Resources/catalog"), // symlink to catalog
                .copy("Resources/colormap.png"), // symlink to the Kenney character texture
                .copy("Resources/Icons"), // the menu bar icon (menubar.png, menubar@2x.png)
                .process("Resources/Localization"), // <lang>.lproj/Localizable.strings
            ]
        ),
        .testTarget(name: "TownCoreTests", dependencies: ["TownCore"]),
    ],
    swiftLanguageModes: [.v5]
)
