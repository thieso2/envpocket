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
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "EnvPocket",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
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