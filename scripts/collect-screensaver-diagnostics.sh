#!/bin/sh
set -eu

last_interval=${1:-5m}
case "$last_interval" in
    5m|15m|30m|1h|6h|1d) ;;
    *)
        printf 'Usage: %s [5m|15m|30m|1h|6h|1d]\n' "$0" >&2
        exit 64
        ;;
esac

exec /usr/bin/log show \
    --last "$last_interval" \
    --style compact \
    --predicate 'subsystem == "com.prototype.mywallpaper.saver" AND category == "diagnostics"'
