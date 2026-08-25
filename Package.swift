// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OptionTab",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "OptionTab",
            path: "Sources/OptionTab"
        )
    ]
)
