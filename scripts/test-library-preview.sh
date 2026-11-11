#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk_path=${MY_WALLPAPER_SDK:-$(xcrun --sdk macosx --show-sdk-path)}
mkdir -p "$repo_dir/.build/module-cache"
swiftc -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
    -strict-concurrency=complete -warnings-as-errors \
    -sdk "$sdk_path" -module-cache-path "$repo_dir/.build/module-cache" \
    -o "$repo_dir/.build/library-preview-tests" \
    "$repo_dir/Sources/MyWallpaper/LibraryVideoPlayback.swift" \
    "$repo_dir/Sources/MyWallpaper/LibraryVideoPreview.swift" \
    "$repo_dir/Sources/MyWallpaper/RetroDesignSystem.swift" \
    "$repo_dir/Tests/MyWallpaperPreviewTests/main.swift"
test_bundle="$repo_dir/.build/Library Preview Tests.app"
mkdir -p "$test_bundle/Contents/MacOS"
cp "$repo_dir/.build/library-preview-tests" "$test_bundle/Contents/MacOS/LibraryPreviewTests"
cat > "$test_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LibraryPreviewTests</string>
<key>CFBundleIdentifier</key><string>com.prototype.mywallpaper.preview-tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
log_path="$repo_dir/.build/library-preview-tests.log"
: > "$log_path"
/usr/bin/open -W -n --stdout "$log_path" --stderr "$log_path" "$test_bundle"
cat "$log_path"
rg -q '^Preview tests passed:' "$log_path"
