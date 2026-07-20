// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuotaRing",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CodexQuotaRing",
            path: "Sources/CodexQuotaRing"
        )
    ]
)
