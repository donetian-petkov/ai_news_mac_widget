// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AINewsMacWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AINewsWidgetShared", targets: ["AINewsWidgetShared"]),
        .library(name: "AINewsWidgetExtensionSupport", targets: ["AINewsWidgetExtensionSupport"]),
        .executable(name: "AINewsMacApp", targets: ["AINewsMacApp"])
    ],
    targets: [
        .target(
            name: "AINewsWidgetShared",
            path: "Sources/AINewsWidgetShared"
        ),
        .target(
            name: "AINewsWidgetExtensionSupport",
            dependencies: ["AINewsWidgetShared"],
            path: "Sources/AINewsWidgetExtensionSupport"
        ),
        .executableTarget(
            name: "AINewsMacApp",
            dependencies: ["AINewsWidgetShared"],
            path: "Sources/AINewsMacApp"
        ),
        .testTarget(
            name: "AINewsWidgetSharedTests",
            dependencies: ["AINewsWidgetShared"],
            path: "Tests/AINewsWidgetSharedTests"
        )
    ]
)
