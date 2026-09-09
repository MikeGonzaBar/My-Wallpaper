#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_dir/support/version.env"

signature_mode=${1:-adhoc}
expected_team_id=${2:-}
case "$signature_mode" in
    adhoc) ;;
    developer-id)
        if [ -z "$expected_team_id" ]; then
            printf 'Developer ID verification requires an expected team identifier.\n' >&2
            exit 64
        fi
        ;;
    *)
        printf 'Usage: %s [adhoc|developer-id [team-id]]\n' "$0" >&2
        exit 64
        ;;
esac

app="$repo_dir/dist/My Wallpaper.app"
saver="$app/Contents/Resources/My Wallpaper.saver"
app_binary="$app/Contents/MacOS/MyWallpaper"
saver_binary="$saver/Contents/MacOS/MyWallpaperScreenSaver"

codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --deep --strict --verbose=2 "$saver"

for binary in "$app_binary" "$saver_binary"; do
    architectures=$(lipo -archs "$binary")
    printf '%s\n' "$architectures" | grep -Eq '(^| )arm64( |$)'
    printf '%s\n' "$architectures" | grep -Eq '(^| )x86_64( |$)'
    test "$(vtool -show-build "$binary" | grep -c 'minos 14.0')" -eq 2
done

for bundle in "$app" "$saver"; do
    details=$(codesign -dv --verbose=4 "$bundle" 2>&1)
    printf '%s\n' "$details" | grep -Eq 'flags=.*runtime'
    if [ "$signature_mode" = developer-id ]; then
        printf '%s\n' "$details" | grep -q 'Authority=Developer ID Application'
        printf '%s\n' "$details" | grep -q "TeamIdentifier=$expected_team_id"
    fi
done

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$MY_WALLPAPER_MARKETING_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$MY_WALLPAPER_BUILD_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$saver/Contents/Info.plist")" = "$MY_WALLPAPER_MARKETING_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$saver/Contents/Info.plist")" = "$MY_WALLPAPER_BUILD_VERSION"

entitlements=$(mktemp "$repo_dir/.build/verified-entitlements.XXXXXX")
cleanup() {
    rm -f "$entitlements"
}
trap cleanup EXIT INT TERM
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$entitlements")" = true
if [ "$signature_mode" = developer-id ]; then
    test "$(/usr/libexec/PlistBuddy -c 'Print' "$entitlements" | grep -c '=')" -eq 1
fi

printf 'Verified %s release contract for %s\n' "$signature_mode" "$app"
