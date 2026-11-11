#!/bin/sh
set -eu
mode=${1:-run}
case "$mode" in
    run|--debug|--logs|--telemetry|--verify) ;;
    *) printf 'Usage: %s [--debug|--logs|--telemetry|--verify]\n' "$0" >&2; exit 2 ;;
esac
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_bundle="$repo_dir/dist/My Wallpaper.app"
if pgrep -x MyWallpaper >/dev/null; then
    pkill -TERM -x MyWallpaper
fi
"$repo_dir/scripts/package-app.sh" debug
case "$mode" in
    --debug) exec lldb -- "$app_bundle/Contents/MacOS/MyWallpaper" ;;
esac
/usr/bin/open -n "$app_bundle"
case "$mode" in
    --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "MyWallpaper"' ;;
    --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.prototype.mywallpaper"' ;;
    --verify)
        for attempt in 1 2 3 4 5; do
            if pgrep -x MyWallpaper >/dev/null; then exit 0; fi
            sleep 1
        done
        printf 'My Wallpaper did not start.\n' >&2
        exit 1
        ;;
esac
