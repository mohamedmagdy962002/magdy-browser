"""Generates the Magdy Browser app icon (1024x1024 PNG, stdlib only).

Run:  python scripts/generate_icon.py
"""

import math
import os
import struct
import zlib

SIZE = 1024
STROKE = 92.0


def lerp(a, b, t):
    return a + (b - a) * t


def gradient(x, y):
    t = (x + y) / (2.0 * SIZE)
    return (
        int(lerp(74, 138, t)),
        int(lerp(71, 63, t)),
        int(lerp(240, 252, t)),
    )


def segment_distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    length2 = vx * vx + vy * vy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / length2))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


def build_pixels():
    # M shape: left leg, left diagonal, right diagonal, right leg.
    segments = [
        (300, 300, 300, 740),
        (300, 740, 512, 470),
        (512, 470, 724, 740),
        (724, 740, 724, 300),
    ]
    rows = []
    for y in range(SIZE):
        row = bytearray()
        for x in range(SIZE):
            r, g, b = gradient(x, y)
            inside = False
            for (ax, ay, bx, by) in segments:
                if segment_distance(x + 0.5, y + 0.5, ax, ay, bx, by) <= STROKE / 2:
                    inside = True
                    break
            if inside:
                r = g = b = 255
            row += bytes((r, g, b))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        payload = tag + data
        return (
            struct.pack(">I", len(data))
            + payload
            + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
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
    out = os.path.join(
        root, "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write_png(out, build_pixels())
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
