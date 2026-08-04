#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon=${1:-"$repo_dir/assets/classic_mac_my_wallpaper_logo.png"}
temporary_dir=$(mktemp -d "$repo_dir/.build/MyWallpaperIcon.XXXXXX")
iconset_dir="$temporary_dir/MyWallpaper.iconset"
mkdir -p "$iconset_dir"

cleanup() {
    rm -rf "$temporary_dir"
}
trap cleanup EXIT INT TERM

if [ ! -f "$source_icon" ]; then
    printf 'Missing source icon: %s\n' "$source_icon" >&2
    exit 1
fi

render_icon() {
    size=$1
    filename=$2
    sips -z "$size" "$size" "$source_icon" --out "$iconset_dir/$filename" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

sips -s format png "$source_icon" --out "$repo_dir/assets/MyWallpaperIcon.png" >/dev/null
sips -s format png "$source_icon" --out "$repo_dir/assets/MyWallpaperIcon-chroma.png" >/dev/null
python3 "$repo_dir/scripts/build-icns.py" \
    "$iconset_dir" \
    "$repo_dir/assets/MyWallpaper.icns"

printf 'Updated My Wallpaper icon assets from %s\n' "$source_icon"
