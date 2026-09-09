// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SocialCooldown",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SocialCooldown", targets: ["SocialCooldown"])
    ],
    targets: [
        .executableTarget(
            name: "SocialCooldown",
            path: "Sources/SocialCooldown"
        ),
        .testTarget(
            name: "SocialCooldownTests",
            dependencies: ["SocialCooldown"],
            path: "Tests/SocialCooldownTests"
        )
    ]
)
