// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CAVI",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(name: "CAVICore"),
        .executableTarget(
            name: "CAVI",
            dependencies: ["CAVICore"],
            path: "Sources/CAVI",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "SafetyTestRunner",
            dependencies: ["CAVICore"],
            path: "Sources/SafetyTestRunner"
        ),
        .testTarget(
            name: "CAVICoreTests",
            dependencies: ["CAVICore"],
            path: "Tests/CAVICoreTests"
        ),
        .testTarget(
            name: "CAVIIntegrationTests",
            dependencies: ["CAVI"],
            path: "Tests/CAVIIntegrationTests"
        )
    ]
)
