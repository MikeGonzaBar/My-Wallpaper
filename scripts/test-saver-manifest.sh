#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir="$repo_dir/.build/screensaver-tests"
module_cache_dir="$repo_dir/.build/objc-module-cache"
manifest_test_binary="$test_dir/ManifestParserTests"
playback_test_binary="$test_dir/PlaybackLifecycleTests"
display_resolver_test_binary="$test_dir/DisplayResolverTests"
diagnostics_test_binary="$test_dir/DiagnosticsTests"

if [ -n "${MY_WALLPAPER_SDK:-}" ]; then
    sdk_path=$MY_WALLPAPER_SDK
else
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$test_dir" "$module_cache_dir"
clang \
    -isysroot "$sdk_path" \
    -mmacosx-version-min=14.0 \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache_dir" \
    -Wall \
    -Wextra \
    -Werror \
    -framework Foundation \
    -I "$repo_dir/Sources/MyWallpaperScreenSaver" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDiagnostics.m" \
    "$repo_dir/Tests/MyWallpaperScreenSaverTests/DiagnosticsTests.m" \
    -o "$diagnostics_test_binary"

"$diagnostics_test_binary"

clang \
    -isysroot "$sdk_path" \
    -mmacosx-version-min=14.0 \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache_dir" \
    -Wall \
    -Wextra \
    -Werror \
    -framework Foundation \
    -I "$repo_dir/Sources/MyWallpaperScreenSaver" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDiagnostics.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverManifest.m" \
    "$repo_dir/Tests/MyWallpaperScreenSaverTests/ManifestParserTests.m" \
    -o "$manifest_test_binary"

"$manifest_test_binary"

clang \
    -isysroot "$sdk_path" \
    -mmacosx-version-min=14.0 \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache_dir" \
    -Wall \
    -Wextra \
    -Werror \
    -framework AppKit \
    -framework CoreGraphics \
    -I "$repo_dir/Sources/MyWallpaperScreenSaver" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDiagnostics.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDisplayResolver.m" \
    "$repo_dir/Tests/MyWallpaperScreenSaverTests/DisplayResolverTests.m" \
    -o "$display_resolver_test_binary"

"$display_resolver_test_binary"

clang \
    -isysroot "$sdk_path" \
    -mmacosx-version-min=14.0 \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache_dir" \
    -Wall \
    -Wextra \
    -Werror \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework ScreenSaver \
    -I "$repo_dir/Sources/MyWallpaperScreenSaver" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDiagnostics.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDisplayResolver.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverManifest.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/VideoScreenSaverView.m" \
    "$repo_dir/Tests/MyWallpaperScreenSaverTests/PlaybackLifecycleTests.m" \
    -o "$playback_test_binary"

"$playback_test_binary"
