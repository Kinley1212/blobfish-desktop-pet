// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlobfishNativePrototype",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BlobfishNative", targets: ["BlobfishNative"]),
    ],
    targets: [
        .executableTarget(
            name: "BlobfishNative",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "BlobfishNativeTests",
            dependencies: ["BlobfishNative"]
        ),
    ]
)
