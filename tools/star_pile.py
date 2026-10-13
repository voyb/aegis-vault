#!/usr/bin/env python3
"""Draws the README "star pile": one gold star for every GitHub star, heaped into a mound, with the real count and a thank-you.

  python3 tools/star_pile.py 84 -o stars.svg

Deterministic: star number i always lands in the same spot, so a new star simply drops on top of the pile and the old ones never
move. Stdlib only. The picture works on light and dark pages (it carries its own dark card). The GitHub Action in
.github/workflows/stars.yml runs this daily and whenever someone stars the repo, and publishes the result to the `stars` branch.
"""
import argparse
import math
import sys

W, H = 960, 420
PILE = (36, 30, 560, 360)            # x, y, width, height of the box the pile has to fit in
PALETTE = [("#fff3a0", "#ffd60a", "#c98f00"), ("#ffe14d", "#f7b500", "#b87b00"), ("#ffd23c", "#e8a200", "#a56b00"), ("#fff8c8", "#ffe066", "#d9a400")]


def lcg(i: int, k: int) -> float:
    x = (i * 2654435761 + k * 40503 + 12345) & 0xFFFFFFFF
    x ^= x >> 15
    x = (x * 2246822519) & 0xFFFFFFFF
    x ^= x >> 13
    return (x & 0xFFFFFF) / float(0x1000000)


def slots(size: float):
    """Mound slots from the bottom row up, centre first inside each row. Returns [(x, y, row)] sized to the pile box."""
    bx, by, bw, bh = PILE
    d = size * 0.82
    rows = []
    row_h = d * 0.78
    k = 0
    while (k + 1) * row_h + size * 0.5 <= bh:
        frac = k * row_h / max(1.0, bh - size)
        width = bw * (1.0 - frac ** 1.35) ** 0.5
        n = int(width // d)
        if n < 1:
            break
        rows.append(n)
        k += 1
    out = []
    for r, n in enumerate(rows):
        y = by + bh - size * 0.5 - r * row_h
        off = (d / 2.0) if (r % 2) else 0.0
        cx = bx + bw / 2.0
        order = sorted(range(n), key=lambda j: abs(j - (n - 1) / 2.0))
        for j in order:
            x = cx + (j - (n - 1) / 2.0) * d + (off if n > 1 else 0.0) - (d / 4.0 if r % 2 else 0.0)
            out.append((x, y, r))
    return out


def star_points(cx, cy, ro, ri, rot):
    pts = []
    for k in range(10):
        r = ro if k % 2 == 0 else ri
        a = rot + k * math.pi / 5 - math.pi / 2
        pts.append("%.1f,%.1f" % (cx + math.cos(a) * r, cy + math.sin(a) * r))
    return " ".join(pts)


MAX_DRAWN = 1200                      # past this the pile stops growing (one drawn star then stands for several real ones)


def render(n: int, stamp: str = "") -> str:
    drawn = min(n, MAX_DRAWN)
    each = -(-n // drawn) if drawn else 1
    size = 46.0
    pos = slots(size)
    while len(pos) < drawn and size > 3.0:
        size *= 0.93
        pos = slots(size)
    pos = pos[:drawn]
    out = (["<!-- drawn %s -->" % stamp.replace("--", "-")] if stamp else []) + ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="%d GitHub stars">' % (W, H, W, H, n),
           "<title>%d GitHub stars. Thank you for using my vault.</title>" % n,
           "<defs>",
           '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#15131a"/><stop offset="1" stop-color="#08070a"/></linearGradient>',
           '<linearGradient id="num" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff6b8"/><stop offset=".5" stop-color="#ffd60a"/><stop offset="1" stop-color="#b87b00"/></linearGradient>',
           '<radialGradient id="glow" cx=".35" cy="1" r=".75"><stop offset="0" stop-color="#ffcf3a" stop-opacity=".22"/><stop offset="1" stop-color="#ffcf3a" stop-opacity="0"/></radialGradient>',
           '<filter id="soft" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="#000" flood-opacity=".55"/></filter>']
    for i, (a, b, c) in enumerate(PALETTE):
        out.append('<linearGradient id="g%d" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset=".55" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % (i, a, b, c))
    out += ["</defs>",
            '<rect x="1" y="1" width="%d" height="%d" rx="22" fill="url(#bg)" stroke="#6b5420" stroke-opacity=".7"/>' % (W - 2, H - 2),
            '<rect x="1" y="1" width="%d" height="%d" rx="22" fill="url(#glow)"/>' % (W - 2, H - 2),
            '<g filter="url(#soft)">']
    for i, (x, y, row) in enumerate(pos):
        jx, jy = (lcg(i, 1) - 0.5) * size * 0.22, (lcg(i, 2) - 0.5) * size * 0.14
        s = size * (0.46 + 0.07 * lcg(i, 3))
        rot = (lcg(i, 4) - 0.5) * 0.9
        g = int(lcg(i, 5) * len(PALETTE))
        cx, cy = x + jx, y + jy
        out.append('<polygon points="%s" fill="url(#g%d)" stroke="#8a5a00" stroke-width=".7" stroke-linejoin="round"/>' % (star_points(cx, cy, s, s * 0.42, rot), g))
        out.append('<polygon points="%s" fill="#fff" fill-opacity=".38"/>' % star_points(cx - s * 0.12, cy - s * 0.16, s * 0.34, s * 0.14, rot))
    out.append("</g>")
    label = "{:,}".format(n)
    fs = 150 if len(label) <= 3 else (120 if len(label) <= 5 else 96)
    out += ['<text x="610" y="175" font-family="Georgia,\'Times New Roman\',serif" font-size="%d" font-weight="700" fill="url(#num)">%s</text>' % (fs, label),
            '<text x="614" y="214" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="17" letter-spacing="3" fill="#cdbf8f">%s</text>' % ("PEOPLE STARRED AEGIS" if n != 1 else "PERSON STARRED AEGIS"),
            '<line x1="614" y1="238" x2="900" y2="238" stroke="#6b5420" stroke-opacity=".8"/>',
            '<text x="614" y="285" font-family="Georgia,\'Times New Roman\',serif" font-size="27" font-style="italic" fill="#f4efe0">Thank you for using my vault.</text>',
            '<text x="614" y="318" font-family="system-ui,-apple-system,Segoe UI,Roboto,sans-serif" font-size="15" fill="#a39a80">One gold star for every star on GitHub.</text>',
            '<text x="614" y="352" font-family="Georgia,\'Times New Roman\',serif" font-size="19" fill="#ffd60a">- voyb</text>',
            ('<text x="614" y="388" font-family="system-ui,sans-serif" font-size="12" fill="#7d7660">Each star drawn here stands for %d stars.</text>' % each) if each > 1 else "",
            "</svg>"]
    return "\n".join(out) + "\n"


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Draw the README star pile for N stars.")
    p.add_argument("count", type=int, help="the real GitHub star count")
    p.add_argument("-o", "--out", default="-", help="output file (default: stdout)")
    p.add_argument("--stamp", default="", help="a date to write into the file, so a daily run always changes it (keeps the schedule alive)")
    a = p.parse_args(argv)
    if a.count < 0 or a.count > 10_000_000:
        print("count out of range", file=sys.stderr)
        return 2
    svg = render(a.count, a.stamp)
    if a.out == "-":
        sys.stdout.write(svg)
    else:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
