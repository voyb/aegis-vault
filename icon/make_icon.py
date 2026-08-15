"""Generates icon/aegis_1024.png (master), icon/aegis.ico (Windows),
icon/aegis.icns (macOS), and icon/aegis_256.png / aegis_512.png (Linux)
from scratch with Pillow - no SVG rasterizer needed.

Run: python icon/make_icon.py
"""
import struct
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).parent
SIZE = 1024

BG_TOP = (20, 20, 24, 255)      # #141418
BG_BOTTOM = (8, 8, 10, 255)     # #08080a
BORDER = (58, 58, 66, 255)      # #3a3a42
GOLD_LIGHT = (239, 217, 160, 255)  # #efd9a0
GOLD_DARK = (201, 168, 106, 255)   # #c9a86a
SHIELD_STROKE = (10, 10, 12, 255)  # #0a0a0c


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGBA", (1, size), color=0)
    for y in range(size):
        t = y / (size - 1)
        px = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        grad.putpixel((0, y), px)
    return grad.resize((size, size))


def diagonal_gradient(size, a, b):
    grad = Image.new("RGBA", (size, size), color=0)
    px = grad.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))
    return grad


def _cubic_bezier_points(p0, c1, c2, p1, n=24):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        mt = 1 - t
        x = (mt**3) * p0[0] + 3 * (mt**2) * t * c1[0] + 3 * mt * (t**2) * c2[0] + (t**3) * p1[0]
        y = (mt**3) * p0[1] + 3 * (mt**2) * t * c1[1] + 3 * mt * (t**2) * c2[1] + (t**3) * p1[1]
        pts.append((x, y))
    return pts


def shield_points(size):
    """Same silhouette as the in-app favicon shield (pointed top, curved base),
    traced from its SVG path 'M12 3 5 6v5c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3Z'
    (a 24x24 viewBox), scaled and centered onto `size`x`size`."""
    scale = size * 0.62 / 14
    offx = (size - 14 * scale) / 2
    offy = (size - 17 * scale) / 2

    def tr(x, y):
        return ((x - 5) * scale + offx, (y - 3) * scale + offy)

    p_top = tr(12, 3)
    p_shoulder_l = tr(5, 6)
    p_side_l = tr(5, 11)
    p_bottom = tr(12, 20)
    p_side_r = tr(19, 11)
    p_shoulder_r = tr(19, 6)

    curve1 = _cubic_bezier_points(p_side_l, tr(5, 15.5), tr(8, 18.5), p_bottom)
    curve2 = _cubic_bezier_points(p_bottom, tr(16, 18.5), tr(19, 15.5), p_side_r)

    return [p_top, p_shoulder_l, p_side_l] + curve1 + curve2 + [p_shoulder_r]


def shield_mask(size):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.polygon(shield_points(size), fill=255)
    return m


def rounded_square_mask(size, radius_frac=0.22):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = int(size * radius_frac)
    d.rounded_rectangle([(0, 0), (size - 1, size - 1)], radius=r, fill=255)
    return m


def build_master():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    bg_grad = vertical_gradient(SIZE, BG_TOP, BG_BOTTOM)
    bg_mask = rounded_square_mask(SIZE)
    canvas.paste(bg_grad, (0, 0), bg_mask)

    # subtle border ring
    border_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border_layer)
    r = int(SIZE * 0.22)
    bd.rounded_rectangle([(2, 2), (SIZE - 3, SIZE - 3)], radius=r, outline=BORDER, width=4)
    canvas.alpha_composite(border_layer)

    gold_grad = diagonal_gradient(SIZE, GOLD_LIGHT, GOLD_DARK)
    s_mask = shield_mask(SIZE)
    shield_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shield_layer.paste(gold_grad, (0, 0), s_mask)

    # thin dark outline around the shield for contrast
    outline_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(outline_layer)
    pts = shield_points(SIZE)
    od.polygon(pts, outline=SHIELD_STROKE, width=10)
    canvas.alpha_composite(shield_layer)
    canvas.alpha_composite(outline_layer)

    canvas.save(HERE / "aegis_1024.png")
    return canvas


def build_ico(master):
    sizes = [16, 24, 32, 48, 64, 128, 256]
    imgs = [master.resize((s, s), Image.LANCZOS) for s in sizes]
    imgs[-1].save(HERE / "aegis.ico", sizes=[(s, s) for s in sizes])


def build_pngs(master):
    for s in (256, 512):
        master.resize((s, s), Image.LANCZOS).save(HERE / f"aegis_{s}.png")


ICNS_TYPES = {
    16: b"icp4", 32: b"icp5", 64: b"icp6",
    128: b"ic07", 256: b"ic08", 512: b"ic09", 1024: b"ic10",
}


def build_icns(master):
    """Minimal ICNS writer: PNG-backed entries, no native deps needed."""
    import io
    entries = b""
    for size, tag in ICNS_TYPES.items():
        img = master.resize((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        data = buf.getvalue()
        entries += tag + struct.pack(">I", len(data) + 8) + data
    total_len = 8 + len(entries)
    with open(HERE / "aegis.icns", "wb") as f:
        f.write(b"icns" + struct.pack(">I", total_len) + entries)


if __name__ == "__main__":
    master = build_master()
    build_ico(master)
    build_icns(master)
    build_pngs(master)
    print("Wrote aegis_1024.png, aegis.ico, aegis.icns, aegis_256.png, aegis_512.png")
