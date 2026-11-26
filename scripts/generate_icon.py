"""Generates canonical Magdy M brand artwork using only the Python standard library."""

import math
import os
import struct
import zlib

BACKGROUND = (0xEA, 0x54, 0x00)
FOREGROUND = (0xFE, 0xFB, 0xF8)


def segment_distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    length2 = vx * vx + vy * vy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / length2))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


def build_pixels(size):
    scale = size / 1024.0
    stroke = 92.0 * scale
    segments = [
        (300, 740, 300, 300),
        (300, 300, 512, 520),
        (512, 520, 724, 300),
        (724, 300, 724, 740),
    ]
    segments = [
        (ax * scale, ay * scale, bx * scale, by * scale)
        for ax, ay, bx, by in segments
    ]
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            inside = any(
                segment_distance(x + 0.5, y + 0.5, ax, ay, bx, by) <= stroke / 2
                for ax, ay, bx, by in segments
            )
            row += bytes(FOREGROUND if inside else BACKGROUND)
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    size = len(rows)
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        payload = tag + data
        return (
            struct.pack(">I", len(data))
            + payload
            + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(png)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    outputs = [
        (1024, os.path.join(root, "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")),
        (512, os.path.join(root, "Resources", "Assets.xcassets", "LaunchLogo.imageset", "LaunchLogo.png")),
    ]
    for size, path in outputs:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_png(path, build_pixels(size))
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
