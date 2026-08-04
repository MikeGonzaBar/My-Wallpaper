#!/usr/bin/env python3
"""Create a modern ICNS container from a macOS iconset directory."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


ICON_RESOURCES = (
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
)


def build_icns(iconset_directory: Path, destination: Path) -> None:
    chunks: list[bytes] = []

    for resource_type, filename in ICON_RESOURCES:
        source = iconset_directory / filename
        if not source.is_file():
            raise FileNotFoundError(f"Missing icon resource: {source}")

        payload = source.read_bytes()
        chunks.append(resource_type + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    destination.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: build-icns.py ICONSET_DIRECTORY DESTINATION")

    build_icns(Path(sys.argv[1]), Path(sys.argv[2]))


if __name__ == "__main__":
    main()
