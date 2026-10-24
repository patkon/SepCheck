// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SepCheck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SepCheck", path: "Sources/SepCheck")
    ]
)
