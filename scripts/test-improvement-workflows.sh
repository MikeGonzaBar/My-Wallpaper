#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_path=${MY_WALLPAPER_SDK:-$(xcrun --sdk macosx --show-sdk-path)}
module_cache_dir="$repo_dir/.build/module-cache"
test_binary="$repo_dir/.build/improvement-workflow-tests"
mkdir -p "$module_cache_dir"
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    -sdk "$sdk_path" -module-cache-path "$module_cache_dir" \
    -framework SwiftUI -framework VideoToolbox \
    -o "$test_binary" \
    "$repo_dir/Sources/MyWallpaper/WallpaperSettings.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoOptimizer.swift" \
    "$repo_dir/Sources/MyWallpaper/ManagedVideoFileStore.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoLibraryModels.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoContentFingerprint.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoLibraryImporter.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoLibraryRecovery.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoLibraryStorage.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoLibrarySnapshot.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoOptimizationCoordinator.swift" \
    "$repo_dir/Sources/MyWallpaper/PlaylistEditing.swift" \
    "$repo_dir/Sources/MyWallpaper/PlaylistAssignmentEditor.swift" \
    "$repo_dir/Sources/MyWallpaper/MainWindowRegistry.swift" \
    "$repo_dir/Tests/MyWallpaperImprovementTests/main.swift"
"$test_binary"
