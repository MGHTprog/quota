// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Quota",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Quota", targets: ["Quota"])
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/SweetCookieKit.git", exact: "0.5.2")
    ],
    targets: [
        .executableTarget(
            name: "Quota",
            dependencies: [.product(name: "SweetCookieKit", package: "SweetCookieKit")],
            path: "Sources/Quota",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "QuotaTests",
            dependencies: ["Quota"],
            path: "Tests/QuotaTests"
        )
    ]
)
