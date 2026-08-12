// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HaloLayer",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HaloLayer",
            path: "HaloLayer",
            exclude: ["Info.plist", "HaloLayer.entitlements"]
        ),
        .testTarget(
            name: "HaloLayerTests",
            dependencies: ["HaloLayer"],
            path: "HaloLayerTests",
            exclude: ["Info.plist"]
        )
    ]
)
