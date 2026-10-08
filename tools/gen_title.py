"""
The DON'T LOOK AWAY title as scratched lettering (original, procedural: every
letter is a set of hand-defined strokes drawn as many jittered scratches in
white, over a smeared red layer). Writes assets/marketing/title_dla.png
(transparent, 1024x640) and title_preview.png (on black).

    python3 tools/gen_title.py
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "marketing")
W, H = 1024, 640
SS = 2  # supersampling
rng = np.random.default_rng(31)


def ellipse(cx, cy, rx, ry, n=22, start=-0.3):
    return [(cx + rx * math.cos(start + 2 * math.pi * i / n), cy + ry * math.sin(start + 2 * math.pi * i / n)) for i in range(n + 2)]


# strokes per glyph in a unit box (x right, y down); width of the glyph
GLYPHS = {
    "D": (0.62, [[(0, 0), (0, 1)], [(0, 0.02), (0.32, 0.04), (0.56, 0.2), (0.62, 0.5), (0.55, 0.8), (0.32, 0.97), (0, 1)]]),
    "O": (0.66, [ellipse(0.33, 0.5, 0.33, 0.5)]),
    "N": (0.62, [[(0, 1), (0, 0)], [(0, 0), (0.62, 1)], [(0.62, 1), (0.62, 0)]]),
    "'": (0.14, [[(0.08, -0.02), (0.0, 0.26)]]),
    "T": (0.64, [[(-0.04, 0.02), (0.68, -0.01)], [(0.32, 0.0), (0.31, 1)]]),
    "L": (0.52, [[(0, 0), (0, 1), (0.54, 0.98)]]),
    "K": (0.62, [[(0, 0), (0, 1)], [(0.6, 0), (0.02, 0.56)], [(0.16, 0.42), (0.64, 1)]]),
    "A": (0.68, [[(0, 1), (0.34, 0), (0.68, 1)], [(0.13, 0.64), (0.55, 0.6)]]),
    "W": (0.9, [[(0, 0), (0.2, 1), (0.44, 0.32), (0.66, 1), (0.9, -0.02)]]),
    "Y": (0.64, [[(0, 0), (0.33, 0.52), (0.66, -0.02)], [(0.33, 0.52), (0.3, 1)]]),
    " ": (0.36, []),
}


def densify(points, step=0.06):
    out = []
    for (x0, y0), (x1, y1) in zip(points[:-1], points[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / step))
        for i in range(n):
            t = i / n
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    out.append(points[-1])
    return out


def layout(lines):
    """Strokes in pixels for each line: (text, x, baseline_y, height, rotation)."""
    strokes = []
    for text, x, y, h, rot in lines:
        cx = x
        for ch in text:
            gw, gs = GLYPHS[ch]
            # each letter a little different: size, lean, offset
            hh = h * rng.uniform(0.9, 1.08)
            lean = rng.uniform(0.08, 0.2)
            dy = rng.uniform(-0.05, 0.05) * h
            for s in gs:
                pts = []
                for px, py in densify(s):
                    X = cx + (px + (1 - py) * lean) * hh
                    Y = y - hh + py * hh + dy
                    # line rotation around its start
                    r = math.radians(rot)
                    X2 = x + (X - x) * math.cos(r) - (Y - y) * math.sin(r)
                    Y2 = y + (X - x) * math.sin(r) + (Y - y) * math.cos(r)
                    pts.append((X2, Y2))
                strokes.append((pts, hh))
            cx += (gw + 0.12) * hh
    return strokes


def scratch(draw, pts, h, color, passes, spread, width_range, alpha_range):
    for _ in range(passes):
        off = rng.normal(0, spread * h, 2)
        wob = rng.uniform(0.0, 0.0025) * h
        line = []
        # scratches overshoot their stroke, like a blade that slipped
        start = rng.uniform(-0.1, 0.06)
        end = rng.uniform(0.94, 1.12)
        n = len(pts)
        # extend the ends along the stroke direction
        if n >= 2:
            (ax, ay), (bx, by) = pts[0], pts[1]
            (cx, cy), (ex, ey) = pts[-2], pts[-1]
            pre = [(ax + (ax - bx) * k, ay + (ay - by) * k) for k in (2, 1)] if start < 0 else []
            post = [(ex + (ex - cx) * k, ey + (ey - cy) * k) for k in (1, 2)] if end > 1 else []
            seq = pre + list(pts) + post
        else:
            seq = list(pts)
        m = len(seq)
        for i, (x, y) in enumerate(seq):
            t = i / max(1, m - 1)
            if t < max(0, start) or t > min(1, end):
                continue
            line.append(((x + off[0] + rng.normal(0, wob)) * SS, (y + off[1] + rng.normal(0, wob)) * SS))
        if len(line) < 2:
            continue
        w = int(rng.uniform(*width_range) * SS)
        a = int(rng.uniform(*alpha_range))
        draw.line(line, fill=color + (a,), width=max(1, w), joint="curve")


def main():
    os.makedirs(OUT, exist_ok=True)
    lines = [
        ("DON'T LOOK", 64, 290, 134, -5),
        ("AWAY", 300, 520, 176, -3),
    ]
    strokes = layout(lines)
    red = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    white = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    dr, dw = ImageDraw.Draw(red), ImageDraw.Draw(white)
    for pts, h in strokes:
        # smeared red under the letters
        scratch(dr, pts, h, (130, 6, 8), 7, 0.045, (12, 26), (110, 190))
        # the letter itself: many white-grey scratches
        scratch(dw, pts, h, (236, 230, 224), 10, 0.016, (3, 8), (170, 250))
        scratch(dw, pts, h, (170, 20, 22), 3, 0.03, (1, 3), (120, 200))
        scratch(dw, pts, h, (160, 150, 146), 5, 0.03, (1, 3), (90, 180))
    # loose scratches across the lettering
    for _ in range(26):
        x = rng.uniform(80, 940)
        y = rng.uniform(120, 560)
        ang = rng.uniform(-0.9, -0.4) if rng.random() < 0.7 else rng.uniform(0.3, 0.8)
        length = rng.uniform(40, 180)
        pts = densify([(x, y), (x + math.cos(ang) * length, y + math.sin(ang) * length)], 4)
        scratch(dw, pts, 60, (220, 210, 205), 1, 0.0, (1, 2), (60, 150))
        if rng.random() < 0.5:
            scratch(dr, pts, 60, (150, 8, 10), 1, 0.0, (2, 5), (60, 140))
    # the slash under AWAY
    slash = densify([(300, 610), (520, 580), (760, 548)], 4)
    scratch(dr, slash, 80, (150, 8, 10), 6, 0.02, (6, 14), (90, 170))
    scratch(dw, slash, 80, (230, 222, 216), 5, 0.01, (2, 5), (120, 220))
    # drips from the red
    for _ in range(14):
        x = rng.uniform(150, 900) * SS
        y = rng.uniform(200, 560) * SS
        length = rng.uniform(15, 60) * SS
        dr.line([(x, y), (x + rng.normal(0, 2), y + length)], fill=(110, 4, 6, int(rng.uniform(80, 160))), width=int(rng.uniform(2, 4) * SS))
    red = red.filter(ImageFilter.GaussianBlur(3 * SS))
    # grit: erode the white with noise so it looks scratched into something
    wa = np.asarray(white, np.float32)
    grit = rng.random((H * SS, W * SS)).astype(np.float32)
    wa[..., 3] *= np.clip(0.55 + grit * 0.7, 0, 1)
    white = Image.fromarray(np.clip(wa, 0, 255).astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.6))
    glow = white.filter(ImageFilter.GaussianBlur(5 * SS))
    ga = np.asarray(glow, np.float32)
    ga[..., :3] = np.array([150, 10, 12])
    ga[..., 3] *= 0.6
    glow = Image.fromarray(np.clip(ga, 0, 255).astype(np.uint8), "RGBA")
    out = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    out.alpha_composite(red)
    out.alpha_composite(glow)
    out.alpha_composite(white)
    out = out.resize((W, H), Image.LANCZOS)
    out.save(os.path.join(OUT, "title_dla.png"))
    preview = Image.new("RGBA", (W, H), (6, 6, 7, 255))
    preview.alpha_composite(out)
    preview.convert("RGB").save(os.path.join(OUT, "title_preview.png"))
    print("title written")


if __name__ == "__main__":
    main()
