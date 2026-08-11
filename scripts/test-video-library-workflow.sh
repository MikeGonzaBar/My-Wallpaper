#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
module_cache_dir="$repo_dir/.build/module-cache"
test_binary="$repo_dir/.build/video-library-workflow-tests"

if [ -n "${MY_WALLPAPER_SDK:-}" ]; then
    sdk_path=$MY_WALLPAPER_SDK
elif [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$module_cache_dir"

swiftc \
    -sdk "$sdk_path" \
    -module-cache-path "$module_cache_dir" \
    -framework SwiftUI \
    -o "$test_binary" \
    "$repo_dir/Sources/MyWallpaper/WallpaperSettings.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoContentFingerprint.swift" \
    "$repo_dir/Sources/MyWallpaper/VideoLibraryModels.swift" \
    "$repo_dir/Tests/MyWallpaperLibraryWorkflowTests/main.swift"

"$test_binary"
