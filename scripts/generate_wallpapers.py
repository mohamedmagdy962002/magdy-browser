"""Generates the Magdy wallpaper pack (start-page backgrounds).

Usage:
    python scripts/generate_wallpapers.py [--count 44] [--width 1290] [--height 2796]

Wallpapers are generated procedurally: brand-tinted gradient meshes, soft blobs,
diagonal light bands and fine grain. Output: Resources/Wallpapers/wall-NNN.png
"""

import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

PALETTES = [
    ("#4A47F0", "#8A3FFC", "#0A84FF"),
    ("#0A84FF", "#64D2FF", "#30D158"),
    ("#FF375F", "#FF9F0A", "#BF5AF2"),
    ("#30D158", "#64D2FF", "#0A84FF"),
    ("#8A3FFC", "#FF375F", "#4A47F0"),
    ("#FF9F0A", "#FF375F", "#8A3FFC"),
    ("#1C1C1E", "#4A47F0", "#8A3FFC"),
    ("#2C3040", "#3A5AFF", "#00C2FF"),
]


def hex_to_rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def vertical_gradient(width, height, top, bottom):
    ramp = np.linspace(0, 1, height, dtype=np.float32)[:, None]
    return (np.array(top, dtype=np.float32)[None, None, :] * (1 - ramp[:, :, None])
            + np.array(bottom, dtype=np.float32)[None, None, :] * ramp[:, :, None])


def radial_blob(width, height, cx, cy, radius, color, strength):
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    distance = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / max(radius, 1)
    mask = np.clip(1 - distance, 0, 1) ** 2 * strength
    return mask[:, :, None] * np.array(color, dtype=np.float32)[None, None, :]


def grain(width, height, amount):
    rng = np.random.default_rng()
    noise = rng.normal(0, amount, (height, width, 1)).astype(np.float32)
    return np.repeat(noise, 3, axis=2)


def make_wallpaper(index: int, width: int, height: int, rng) -> Image.Image:
    palette = PALETTES[index % len(PALETTES)]
    base = vertical_gradient(width, height, hex_to_rgb(palette[0]), hex_to_rgb(palette[2]))

    canvas = base.copy()
    for _ in range(4):
        cx = rng.uniform(0, width)
        cy = rng.uniform(0, height)
        radius = rng.uniform(width * 0.3, width * 0.9)
        color = hex_to_rgb(rng.choice(palette))
        canvas = canvas + radial_blob(width, height, cx, cy, radius, color, rng.uniform(0.25, 0.6))

    # diagonal light band
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    ramp = (xs + ys) / (width + height)
    band = np.clip((ramp - rng.uniform(0.2, 0.6)) * rng.uniform(2.0, 4.0), 0, 1) * 18
    canvas = canvas + band[:, :, None]

    canvas = np.clip(canvas + grain(width, height, 3.2), 0, 255).astype(np.uint8)
    image = Image.fromarray(canvas, "RGB")
    return image.filter(ImageFilter.GaussianBlur(radius=0.6))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=44)
    parser.add_argument("--width", type=int, default=1290)
    parser.add_argument("--height", type=int, default=2796)
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "Resources", "Wallpapers")
    os.makedirs(out_dir, exist_ok=True)

    rng = np.random.default_rng(20261112)
    total = 0
    for index in range(args.count):
        path = os.path.join(out_dir, f"wall-{index:03d}.png")
        if os.path.exists(path):
            total += os.path.getsize(path)
            continue
        image = make_wallpaper(index, args.width, args.height, rng)
        image.save(path, "PNG", optimize=False, compress_level=6)
        size = os.path.getsize(path)
        total += size
        print(f"{os.path.basename(path)}  {size // 1024} KB", flush=True)

    print(f"total {total // (1024 * 1024)} MB in {out_dir}")


if __name__ == "__main__":
    main()
