#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$repo_dir/dist/My Wallpaper.app"
dmg_path="$repo_dir/dist/My-Wallpaper.dmg"
staging_dir=$(mktemp -d "$repo_dir/.build/dmg-root.XXXXXX")
output_dir=$(mktemp -d "$repo_dir/.build/dmg-output.XXXXXX")
staged_dmg_path="$output_dir/My-Wallpaper.dmg"
mount_dir=$(mktemp -d "$repo_dir/.build/dmg-mount.XXXXXX")
is_mounted=false

cleanup() {
    if [ "$is_mounted" = true ]; then
        hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    rm -rf "$staging_dir"
    rm -rf "$output_dir"
    rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ ! -d "$app_dir" ]; then
    printf 'Missing %s. Run scripts/package-app.sh first.\n' "$app_dir" >&2
    exit 1
fi

ditto "$app_dir" "$staging_dir/My Wallpaper.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "$repo_dir/dist"
hdiutil create \
    -volname "My Wallpaper" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$staged_dmg_path" >/dev/null

hdiutil attach "$staged_dmg_path" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
is_mounted=true
test -d "$mount_dir/My Wallpaper.app"
test -L "$mount_dir/Applications"
hdiutil detach "$mount_dir" >/dev/null
is_mounted=false
mv -f "$staged_dmg_path" "$dmg_path"

printf 'Created %s\n' "$dmg_path"
