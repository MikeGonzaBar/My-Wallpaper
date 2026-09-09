#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/support/version.env"
build_configuration=${1:-release}
build_dir="$repo_dir/.build/screensaver/$build_configuration"
saver_dir="$build_dir/My Wallpaper.saver"
module_cache_dir="$repo_dir/.build/objc-module-cache"

case "$build_configuration" in
    debug|release) ;;
    *)
        printf 'Usage: %s [debug|release]\n' "$0" >&2
        exit 64
        ;;
esac

sdk_path=${MY_WALLPAPER_SDK:-$(xcrun --sdk macosx --show-sdk-path)}

mkdir -p "$build_dir" "$module_cache_dir"
staging_root=$(mktemp -d "$repo_dir/.build/saver-package.XXXXXX")
staged_saver="$staging_root/My Wallpaper.saver"
contents_dir="$staged_saver/Contents"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"

cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT INT TERM

optimization_flag=-O2
if [ "$build_configuration" = debug ]; then
    optimization_flag=-O0
fi

clang \
    -arch arm64 \
    -arch x86_64 \
    -isysroot "$sdk_path" \
    -mmacosx-version-min=14.0 \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache_dir" \
    "$optimization_flag" \
    -Wall \
    -Wextra \
    -Werror \
    -bundle \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework ScreenSaver \
    -I "$repo_dir/Sources/MyWallpaperScreenSaver" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDiagnostics.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverDisplayResolver.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/ScreenSaverManifest.m" \
    "$repo_dir/Sources/MyWallpaperScreenSaver/VideoScreenSaverView.m" \
    -o "$contents_dir/MacOS/MyWallpaperScreenSaver"

cp "$repo_dir/support/ScreenSaver-Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MY_WALLPAPER_MARKETING_VERSION" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $MY_WALLPAPER_BUILD_VERSION" "$contents_dir/Info.plist"
cp "$repo_dir/assets/MyWallpaper.icns" "$contents_dir/Resources/MyWallpaper.icns"
codesign --force --options runtime --sign - "$staged_saver"

rm -rf "$saver_dir"
mv "$staged_saver" "$saver_dir"

printf '%s\n' "$saver_dir"
