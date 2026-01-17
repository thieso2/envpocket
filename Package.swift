// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnvPocket",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "envpocket",
            targets: ["EnvPocket"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .executableTarget(
            name: "EnvPocket"
        ),
        .testTarget(
            name: "EnvPocketTests",
            dependencies: [
                "EnvPocket",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)