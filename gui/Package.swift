// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IpaInstallGUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "IpaInstallGUI",
            path: "Sources/IpaInstallGUI"
        )
    ]
)
