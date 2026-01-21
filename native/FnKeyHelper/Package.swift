// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FnKeyHelper",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "FnKeyHelper",
            path: "Sources"
        )
    ]
)
