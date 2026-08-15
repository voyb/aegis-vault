"""Generates social/preview.png, GitHub's social preview image (1280x640).

Run: python social/make_banner.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "icon"))
from make_icon import (  # noqa: E402
    shield_points, diagonal_gradient, GOLD_LIGHT, GOLD_DARK, SHIELD_STROKE,
)
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

HERE = Path(__file__).parent
W, H = 1280, 640

FONT_DIR = Path(r"C:\Windows\Fonts")
GOLD = (201, 168, 106, 255)
GOLD_BRIGHT = (239, 217, 160, 255)
WHITE = (233, 233, 238, 255)
MUTED = (140, 140, 150, 255)
BORDER = (58, 58, 66, 255)


def vertical_gradient(w, h, top, bottom):
    grad = Image.new("RGBA", (1, h), color=0)
    for y in range(h):
        t = y / (h - 1)
        px = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        grad.putpixel((0, y), px)
    return grad.resize((w, h))


def tracked_text(draw, xy, text, font, fill, tracking=0):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        w = draw.textlength(ch, font=font)
        x += w + tracking
    return x


def tracked_width(draw, text, font, tracking=0):
    return sum(draw.textlength(ch, font=font) + tracking for ch in text) - tracking


def build():
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    bg = vertical_gradient(W, H, (16, 16, 20, 255), (7, 7, 9, 255))
    canvas.alpha_composite(bg)

    d = ImageDraw.Draw(canvas)
    d.rectangle([(0, 0), (W - 1, H - 1)], outline=BORDER, width=2)

    # shield mark, left side
    shield_size = 260
    shield_canvas = Image.new("RGBA", (shield_size, shield_size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shield_canvas)
    pts = shield_points(shield_size)
    gold_grad = diagonal_gradient(shield_size, GOLD_LIGHT, GOLD_DARK)
    mask = Image.new("L", (shield_size, shield_size), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    shield_canvas.paste(gold_grad, (0, 0), mask)
    sd.polygon(pts, outline=SHIELD_STROKE, width=6)
    canvas.alpha_composite(shield_canvas, (100, (H - shield_size) // 2))

    # wordmark + tagline, right of the shield
    text_x = 430
    title_font = ImageFont.truetype(str(FONT_DIR / "arialbd.ttf"), 96)
    sub_font = ImageFont.truetype(str(FONT_DIR / "segoeui.ttf"), 26)
    tag_font = ImageFont.truetype(str(FONT_DIR / "segoeui.ttf"), 22)
    chip_font = ImageFont.truetype(str(FONT_DIR / "arialbd.ttf"), 18)

    title_y = 190
    tracking = 14
    x = text_x
    x = tracked_text(d, (x, title_y), "AE", title_font, WHITE, tracking)
    x = tracked_text(d, (x, title_y), "G", title_font, GOLD_BRIGHT, tracking)
    x = tracked_text(d, (x, title_y), "IS", title_font, WHITE, tracking)

    d.text((text_x + 4, title_y + 118), "SOVEREIGN VAULT", font=sub_font, fill=GOLD)
    d.text((text_x + 4, title_y + 158),
            "Offline password, identity, and secret vault.",
            font=tag_font, fill=MUTED)
    d.text((text_x + 4, title_y + 188),
            "Argon2id + AES-256-GCM. Zero servers. Zero telemetry.",
            font=tag_font, fill=MUTED)

    # feature chips
    chips = ["ZERO SERVERS", "ARGON2ID", "AES-256-GCM", "CROSS-PLATFORM"]
    cx = text_x + 4
    cy = title_y + 238
    for chip in chips:
        tw = tracked_width(d, chip, chip_font, 2)
        pad = 16
        chip_w = tw + pad * 2
        chip_h = 40
        d.rounded_rectangle([(cx, cy), (cx + chip_w, cy + chip_h)],
                             radius=8, outline=GOLD, width=2)
        tracked_text(d, (cx + pad, cy + 10), chip, chip_font, GOLD_BRIGHT, 2)
        cx += chip_w + 14

    canvas.convert("RGB").save(HERE / "preview.png")


if __name__ == "__main__":
    build()
    print("Wrote social/preview.png")
