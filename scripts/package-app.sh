#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/support/version.env"
build_configuration=${1:-release}
app_dir="$repo_dir/dist/My Wallpaper.app"
contents_dir="$app_dir/Contents"
binary_dir="$repo_dir/.build/$build_configuration"
module_cache_dir="$repo_dir/.build/module-cache"

if [ -n "${MY_WALLPAPER_SDK:-}" ]; then
    sdk_path=$MY_WALLPAPER_SDK
elif [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

cd "$repo_dir"
mkdir -p "$binary_dir" "$module_cache_dir"

optimization_flag=-O
if [ "$build_configuration" = debug ]; then
    optimization_flag=-Onone
fi

swiftc \
    -sdk "$sdk_path" \
    -module-cache-path "$module_cache_dir" \
    -parse-as-library \
    "$optimization_flag" \
    -framework CoreServices \
    -framework IOKit \
    -framework Security \
    -framework VideoToolbox \
    -o "$binary_dir/MyWallpaper" \
    "$repo_dir"/Sources/MyWallpaper/*.swift

saver_dir=$("$repo_dir/scripts/build-saver.sh" "$build_configuration")

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/MyWallpaper" "$contents_dir/MacOS/MyWallpaper"
cp "$repo_dir/support/Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MY_WALLPAPER_MARKETING_VERSION" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $MY_WALLPAPER_BUILD_VERSION" "$contents_dir/Info.plist"
cp "$repo_dir/assets/MyWallpaper.icns" "$contents_dir/Resources/MyWallpaper.icns"
cp -R "$saver_dir" "$contents_dir/Resources/"
codesign --force --options runtime --entitlements "$repo_dir/support/MyWallpaper.entitlements" --sign - "$app_dir"

printf 'Created %s\n' "$app_dir"
