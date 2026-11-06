#!/usr/bin/env python3
"""Draws the MacVolume logo for macOS and Chrome. Needs Pillow and macOS iconutil.

The original LED case is the default; --style ceramic exports the speaker-cone variant.
"""
import argparse
import pathlib
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageOps

SCALE = 2
SIZE = 1024 * SCALE
GREEN, AMBER, RED = (64, 255, 107), (255, 194, 51), (255, 69, 51)
UNLIT = (26, 34, 30)


def s(value):
    return int(value * SCALE)


def vertical_gradient(size, top, bottom):
    column = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        column.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize((size, size))


def rounded_mask(box, radius):
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    return mask


def draw_logo():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body = (s(100), s(100), s(924), s(924))
    mask = rounded_mask(body, s(185))

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (0, s(16)), mask)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s(18))))

    metal = vertical_gradient(SIZE, (92, 97, 112), (30, 32, 40)).convert("RGBA")
    canvas.paste(metal, (0, 0), mask)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(body, s(185), outline=(150, 156, 172, 255), width=s(5))

    for x, y in ((184, 184), (840, 184), (184, 840), (840, 840)):
        r = s(15)
        center = (s(x), s(y))
        draw.ellipse((center[0] - r, center[1] - r, center[0] + r, center[1] + r), fill=(38, 40, 48), outline=(150, 156, 172))
        draw.line((center[0] - r * 0.7, center[1] - r * 0.7, center[0] + r * 0.7, center[1] + r * 0.7), fill=(14, 15, 18), width=s(5))

    well = (s(216), s(216), s(808), s(808))
    draw.rounded_rectangle(well, s(36), fill=(6, 10, 9), outline=(12, 12, 15), width=s(6))
    draw.rounded_rectangle((well[0] - s(5), well[1] - s(5), well[2] + s(5), well[3] + s(5)), s(40), outline=(130, 136, 152), width=s(3))

    columns, rows = 6, 8
    heights = [2, 3, 4, 5, 7, 8]
    left, bottom = 262, 762
    cell_w, cell_h, gap_x, gap_y = 72, 44, 14, 14
    lit = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    lit_draw = ImageDraw.Draw(lit)
    for column in range(columns):
        for row in range(rows):
            x = left + column * (cell_w + gap_x)
            y = bottom - (row + 1) * cell_h - row * gap_y
            box = (s(x), s(y), s(x + cell_w), s(y + cell_h))
            if row < heights[column]:
                color = RED if row >= 6 else AMBER if row >= 4 else GREEN
                lit_draw.rounded_rectangle(box, s(7), fill=color + (255,))
            else:
                draw.rounded_rectangle(box, s(7), fill=UNLIT)
    canvas.alpha_composite(lit.filter(ImageFilter.GaussianBlur(s(20))))
    canvas.alpha_composite(lit)
    return canvas.resize((1024, 1024), Image.LANCZOS)


def draw_ceramic_logo():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body = (s(100), s(100), s(924), s(924))
    mask = rounded_mask(body, s(185))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((23, 33, 58, 65), (0, s(18)), mask)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s(22))))
    canvas.paste(vertical_gradient(SIZE, (255, 255, 255), (218, 226, 238)), (0, 0), mask)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(body, s(185), outline=(245, 248, 255), width=s(3))

    def disk(box, center, rim):
        left, top, right, bottom = [s(v) for v in box]
        size = (right - left, bottom - top)
        radial = Image.radial_gradient("L").resize(size, Image.Resampling.BICUBIC)
        surface = ImageOps.colorize(radial, center, rim).convert("RGBA")
        circle = Image.new("L", size, 0)
        ImageDraw.Draw(circle).ellipse((0, 0, size[0] - 1, size[1] - 1), fill=255)
        canvas.paste(surface, (left, top), circle)

    # Thick porcelain surround, recessed cobalt cone and convex central dust cap.
    disk((194, 194, 830, 830), (132, 145, 170), (243, 247, 253))
    disk((230, 230, 794, 794), (5, 21, 105), (43, 87, 243))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((s(230), s(230), s(794), s(794)), outline=(32, 61, 181), width=s(5))
    draw.arc((s(244), s(244), s(780), s(780)), 30, 150, fill=(83, 128, 255), width=s(4))
    disk((418, 418, 606, 606), (53, 99, 235), (9, 27, 115))
    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chrome-only", action="store_true", help="Export Chrome PNGs without changing the macOS icon")
    parser.add_argument("--style", choices=("ceramic", "retro"), default="retro", help="Icon appearance (default: retro)")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    logo = draw_ceramic_logo() if args.style == "ceramic" else draw_logo()
    chrome_icons = root / "Extensions/Chrome/icons"
    chrome_icons.mkdir(parents=True, exist_ok=True)
    for size in (16, 32, 48, 128):
        logo.resize((size, size), Image.LANCZOS).save(chrome_icons / f"icon{size}.png")
    if args.chrome_only:
        return
    with tempfile.TemporaryDirectory() as temp:
        iconset = pathlib.Path(temp) / "AppIcon.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            logo.resize((points, points), Image.LANCZOS).save(iconset / f"icon_{points}x{points}.png")
            logo.resize((points * 2, points * 2), Image.LANCZOS).save(iconset / f"icon_{points}x{points}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(root / "Resources/AppIcon.icns")], check=True)


if __name__ == "__main__":
    main()
