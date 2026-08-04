#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$repo_dir/dist/My Wallpaper.app"
dmg_path="$repo_dir/dist/My-Wallpaper.dmg"
staging_dir=$(mktemp -d "$repo_dir/.build/dmg-root.XXXXXX")

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

if [ ! -d "$app_dir" ]; then
    printf 'Missing %s. Run scripts/package-app.sh first.\n' "$app_dir" >&2
    exit 1
fi

ditto "$app_dir" "$staging_dir/My Wallpaper.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "$repo_dir/dist"
rm -f "$dmg_path"
hdiutil create \
    -volname "My Wallpaper" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

printf 'Created %s\n' "$dmg_path"
