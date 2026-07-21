"""
Generates the AquaFlow launcher icon (a stylised water drop on the
brand teal gradient) at every Android mipmap density, plus a 1024px
master used for Play Store listing / iOS if that platform is added
later. Run with: python3 tool/generate_launcher_icon.py
"""
from PIL import Image, ImageDraw
import math
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PRIMARY = (10, 110, 140)      # #0A6E8C
PRIMARY_DARK = (5, 79, 102)   # #054F66
WHITE = (255, 255, 255)

DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_drop(draw, cx, cy, size, color):
    # A rounded teardrop: a circle for the bulb + a triangular tip.
    r = size * 0.30
    bulb_cy = cy + size * 0.12
    draw.ellipse(
        [cx - r, bulb_cy - r, cx + r, bulb_cy + r],
        fill=color,
    )
    tip_h = size * 0.42
    points = [
        (cx, bulb_cy - r - tip_h * 0.55),
        (cx - r * 0.92, bulb_cy - r * 0.15),
        (cx + r * 0.92, bulb_cy - r * 0.15),
    ]
    draw.polygon(points, fill=color)


def make_icon(px, supersample=4):
    s = px * supersample
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Diagonal gradient background, rounded corners handled by mask.
    for y in range(s):
        t = y / s
        row_color = lerp(PRIMARY, PRIMARY_DARK, t)
        draw.line([(0, y), (s, y)], fill=row_color)

    mask = Image.new("L", (s, s), 0)
    mdraw = ImageDraw.Draw(mask)
    radius = int(s * 0.22)
    mdraw.rounded_rectangle([0, 0, s, s], radius=radius, fill=255)
    img.putalpha(mask)

    draw_drop(draw, s / 2, s / 2, s * 0.72, WHITE)

    img = img.resize((px, px), Image.LANCZOS)
    return img


def main():
    master = make_icon(1024)
    assets_dir = os.path.join(BASE, "assets", "images")
    os.makedirs(assets_dir, exist_ok=True)
    master.save(os.path.join(assets_dir, "app_icon_master.png"))

    android_res = os.path.join(BASE, "android", "app", "src", "main", "res")
    for folder, size in DENSITIES.items():
        out_dir = os.path.join(android_res, folder)
        os.makedirs(out_dir, exist_ok=True)
        icon = make_icon(size)
        icon.save(os.path.join(out_dir, "ic_launcher.png"))

        # Round icon variant (Android adaptive/round launcher support)
        round_icon = icon.copy()
        round_mask = Image.new("L", (size, size), 0)
        rd = ImageDraw.Draw(round_mask)
        rd.ellipse([0, 0, size, size], fill=255)
        round_icon.putalpha(round_mask)
        round_icon.save(os.path.join(out_dir, "ic_launcher_round.png"))

    print("Generated launcher icons for:", ", ".join(DENSITIES.keys()))


if __name__ == "__main__":
    main()
