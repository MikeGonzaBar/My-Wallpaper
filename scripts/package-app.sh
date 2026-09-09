#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/support/version.env"
build_configuration=${1:-release}
app_dir="$repo_dir/dist/My Wallpaper.app"
binary_dir="$repo_dir/.build/$build_configuration"
module_cache_dir="$repo_dir/.build/module-cache"

case "$build_configuration" in
    debug|release) ;;
    *)
        printf 'Usage: %s [debug|release]\n' "$0" >&2
        exit 64
        ;;
esac

sdk_path=${MY_WALLPAPER_SDK:-$(xcrun --sdk macosx --show-sdk-path)}

cd "$repo_dir"
mkdir -p "$binary_dir" "$module_cache_dir" "$repo_dir/dist"
staging_root=$(mktemp -d "$repo_dir/.build/app-package.XXXXXX")
staged_app="$staging_root/My Wallpaper.app"
contents_dir="$staged_app/Contents"

cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT INT TERM

optimization_flag=-O
if [ "$build_configuration" = debug ]; then
    optimization_flag=-Onone
fi

for architecture in arm64 x86_64; do
    architecture_binary="$binary_dir/MyWallpaper-$architecture"
    mkdir -p "$module_cache_dir/$architecture"
    swiftc \
        -sdk "$sdk_path" \
        -target "$architecture-apple-macosx14.0" \
        -module-cache-path "$module_cache_dir/$architecture" \
        -parse-as-library \
        "$optimization_flag" \
        -framework CoreServices \
        -framework IOKit \
        -framework Security \
        -framework ServiceManagement \
        -framework VideoToolbox \
        -o "$architecture_binary" \
        "$repo_dir"/Sources/MyWallpaper/*.swift
done

lipo -create \
    "$binary_dir/MyWallpaper-arm64" \
    "$binary_dir/MyWallpaper-x86_64" \
    -output "$binary_dir/MyWallpaper"

saver_dir=$("$repo_dir/scripts/build-saver.sh" "$build_configuration")

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/MyWallpaper" "$contents_dir/MacOS/MyWallpaper"
cp "$repo_dir/support/Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MY_WALLPAPER_MARKETING_VERSION" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $MY_WALLPAPER_BUILD_VERSION" "$contents_dir/Info.plist"
cp "$repo_dir/assets/MyWallpaper.icns" "$contents_dir/Resources/MyWallpaper.icns"
cp -R "$saver_dir" "$contents_dir/Resources/"
codesign --force --options runtime --entitlements "$repo_dir/support/MyWallpaper.entitlements" --sign - "$staged_app"

rm -rf "$app_dir"
mv "$staged_app" "$app_dir"

printf 'Created %s\n' "$app_dir"
