// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MyWallpaper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MyWallpaper", targets: ["MyWallpaper"])
    ],
    targets: [
        .executableTarget(
            name: "MyWallpaper",
            path: "Sources/MyWallpaper",
            linkerSettings: [
                .linkedFramework("CoreServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .testTarget(
            name: "MyWallpaperTests",
            dependencies: ["MyWallpaper"],
            path: "Tests/MyWallpaperTests"
        )
    ]
)
