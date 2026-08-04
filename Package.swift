// swift-tools-version: 6.2

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
            path: "Sources/MyWallpaper"
        ),
        .testTarget(
            name: "MyWallpaperTests",
            dependencies: ["MyWallpaper"],
            path: "Tests/MyWallpaperTests"
        )
    ]
)
