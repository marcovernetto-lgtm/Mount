// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mount",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mount", targets: ["Mount"])
    ],
    targets: [
        .executableTarget(
            name: "Mount",
            path: "Sources/Mount",
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "MountTests",
            dependencies: ["Mount"],
            path: "Tests/MountTests"
        )
    ]
)
