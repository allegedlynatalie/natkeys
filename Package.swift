// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Natkeys",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Natkeys", targets: ["Natkeys"]),
    ],
    targets: [
        // Pure logic (dates, weekly shift, combo templates, data model). No AppKit, fully tested.
        .target(name: "NatkeysCore"),
        // The menu bar app: hotkey, popup panel, pasting, settings.
        .executableTarget(name: "Natkeys", dependencies: ["NatkeysCore"]),
        .testTarget(name: "NatkeysCoreTests", dependencies: ["NatkeysCore"]),
    ],
    swiftLanguageModes: [.v5]
)
