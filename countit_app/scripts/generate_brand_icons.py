#!/usr/bin/env python3
"""Generates the launcher icons (COU-55) and splash logos (COU-56) from a vector redraw of the logo.

The original logo (logocountit.webp) is 101x131 px, too small to scale up to a
432 px adaptive foreground or a 1024 px App Store icon. This script redraws it
with the app font (Manrope, assets/fonts): a white "C" and a slanted "It!" in
the accent colour, laid out on the same bounding boxes as the original. Every
PNG is downscaled (Lanczos) from a large master, so the edges stay sharp.

    python3 scripts/generate_brand_icons.py      # requires Pillow

Outputs (overwritten):
  android/app/src/main/res/mipmap-*/ic_launcher{,_foreground,_monochrome}.png
  android/app/src/{local,staging}/res/mipmap-*/ic_launcher{,_foreground}.png
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png (opaque)
  android/app/src/main/res/drawable-*/splash_icon.png
  ios/Runner/Assets.xcassets/LaunchImage.imageset/*.png
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = str(ROOT / "assets/fonts/Manrope-{}.ttf")
RES = ROOT / "android/app/src"
IOS_ICONS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_LAUNCH = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
SPLASH_LOGO_WIDTH = 120  # dp / pt

BACKGROUND = (0x0D, 0x1B, 0x2A, 255)
LETTER_C = (0xF8, 0xF8, 0xF8, 255)
ACCENT = (0x76, 0x8D, 0xAA, 255)
BADGE = (0x77, 0x8D, 0xA9, 255)

# Logo layout in "logo units" (= pixels of the trimmed original, 92x82).
LOGO_W, LOGO_H = 92, 82
C_BOX = (0, 0, 64, 71)  # x, y, w, h
IT_BOX = (61, 57, 31, 25)
# Empty corner right of the "C" and above "It!": where the flavor badge goes.
BADGE_CENTER, BADGE_RADIUS = (80, 25), 11

MASTER_SCALE = 24  # master logo = 2208 x 1968 px
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def _glyph(text: str, weight: str, colour, w: int, h: int, skew: float = 0.0, spacing: float = 0.0) -> Image.Image:
    """Renders text and stretches its ink box to exactly w x h pixels."""
    size = float(h)
    for _ in range(20):  # font size whose ink height is h
        font = ImageFont.truetype(FONT.format(weight), max(1, round(size)))
        box = font.getbbox(text)
        size *= h / (box[3] - box[1])
    font = ImageFont.truetype(FONT.format(weight), round(size))
    canvas = Image.new("RGBA", (h * 6, h * 3), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    x = h * 0.6
    for ch in text:
        draw.text((x, h * 0.6), ch, font=font, fill=colour)
        x += font.getlength(ch) + spacing * h
    if skew:
        canvas = canvas.transform(
            canvas.size, Image.AFFINE, (1, skew, -skew * canvas.size[1] / 2, 0, 1, 0), Image.BICUBIC
        )
    canvas = canvas.crop(canvas.getbbox())
    return canvas.resize((w, h), Image.LANCZOS)


def logo_master(badge: str | None = None, mono: bool = False) -> Image.Image:
    s = MASTER_SCALE
    img = Image.new("RGBA", (LOGO_W * s, LOGO_H * s), (0, 0, 0, 0))
    white = (255, 255, 255, 255)
    x, y, w, h = C_BOX
    img.alpha_composite(_glyph("C", "SemiBold", white if mono else LETTER_C, w * s, h * s), (x * s, y * s))
    x, y, w, h = IT_BOX
    it = _glyph("It!", "ExtraBold", white if mono else ACCENT, w * s, h * s, skew=0.15, spacing=0.14)
    img.alpha_composite(it, (x * s, y * s))
    if badge:
        cx, cy, r = BADGE_CENTER[0] * s, BADGE_CENTER[1] * s, BADGE_RADIUS * s
        draw = ImageDraw.Draw(img)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BADGE)
        letter = _glyph(badge, "ExtraBold", BACKGROUND, round(r * 0.8), round(r * 1.0))
        img.alpha_composite(letter, (cx - letter.width // 2, cy - letter.height // 2))
    return img


def place(logo: Image.Image, size: int, logo_width: float, background=None, corner: float = 0.0) -> Image.Image:
    """Centres the logo (scaled to logo_width px) on a size x size canvas."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if background:
        inset = 0 if not corner else round(size * 2 / 48)  # legacy icons: 44dp art on 48dp
        ImageDraw.Draw(canvas).rounded_rectangle(
            (inset, inset, size - 1 - inset, size - 1 - inset), radius=round(size * corner), fill=background
        )
    w = round(logo_width)
    h = round(w * logo.height / logo.width)
    scaled = logo.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(scaled, ((size - w) // 2, (size - h) // 2))
    return canvas


def android(source_set: str, badge: str | None) -> None:
    logo = logo_master(badge)
    for density, factor in DENSITIES.items():
        out = RES / source_set / "res" / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)
        # Adaptive foreground: 108dp canvas, art inside the 66dp safe circle
        # (the logo's diagonal at 49dp wide is ~65dp).
        place(logo, round(108 * factor), 49 * factor).save(out / "ic_launcher_foreground.png", optimize=True)
        # Legacy icon (API 24-25): rounded square, 44dp art on 48dp.
        place(logo, round(48 * factor), 28 * factor, BACKGROUND, corner=0.18).save(
            out / "ic_launcher.png", optimize=True
        )
        if badge is None:
            mono = logo_master(mono=True)
            place(mono, round(108 * factor), 49 * factor).save(out / "ic_launcher_monochrome.png", optimize=True)


def ios() -> None:
    logo = logo_master()
    contents = json.loads((IOS_ICONS / "Contents.json").read_text())
    for entry in contents["images"]:
        points = float(entry["size"].split("x")[0])
        px = round(points * int(entry["scale"].rstrip("x")))
        # App Store rejects transparency: flatten onto the brand background.
        icon = place(logo, px, px * 0.6, BACKGROUND)
        flat = Image.new("RGB", icon.size, BACKGROUND[:3])
        flat.paste(icon, mask=icon.split()[3])
        flat.save(IOS_ICONS / entry["filename"], optimize=True)


def splash() -> None:
    logo = logo_master()
    for density, factor in DENSITIES.items():
        out = RES / "main/res" / f"drawable-{density}"
        out.mkdir(parents=True, exist_ok=True)
        # Android 12+ splash icon without icon background: 288dp canvas, art
        # inside the 192dp mask circle. Pre-12 launch_background centres the
        # same bitmap, so both splashes look identical.
        place(logo, round(288 * factor), SPLASH_LOGO_WIDTH * factor).save(out / "splash_icon.png", optimize=True)
    w = SPLASH_LOGO_WIDTH
    h = round(w * logo.height / logo.width)
    for scale, name in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")):
        logo.resize((w * scale, h * scale), Image.LANCZOS).save(IOS_LAUNCH / name, optimize=True)


if __name__ == "__main__":
    android("main", None)
    android("local", "L")
    android("staging", "S")
    ios()
    splash()
    print("Icons and splash logos generated.")
