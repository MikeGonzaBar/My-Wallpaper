#!/bin/sh
set -eu

exec /usr/bin/log show \
    --last 5m \
    --style compact \
    --predicate 'subsystem == "com.prototype.mywallpaper.saver" AND category == "diagnostics"'
