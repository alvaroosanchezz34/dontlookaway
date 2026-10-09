"""
Grime decals for DON'T LOOK AWAY (original, procedural, RGBA PNG).

Decals carry the damage a building collects where it logically happens, so the
base materials can stay clean and tileable:

    damp_rising     rising damp along the bottom of a wall, irregular tide line
    water_streak    rain water running down under a window / from a ceiling leak
    grime_smudge    hand dirt around switches and door handles
    ceiling_stain   a ring stain on the ceiling under a leak
    floor_dirt      dirt collected along the foot of a wall (alpha strongest at
                    the wall edge = top of the image)

Every decal fades to zero alpha at its borders so it never shows a hard edge.
The colour is neutral-dark; Roblox multiplies Decal.Color3 on top.

Usage:
    python3 tools/gen_decals.py
"""

import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "decals")


def noise(h, w, beta, seed):
    rng = np.random.default_rng(seed)
    white = rng.normal(size=(h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1
    spec = np.fft.fft2(white) / f ** beta
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def border(h, w, margin):
    y, x = np.mgrid[0:h, 0:w]
    dx = np.minimum(x, w - 1 - x) / (w * margin)
    dy = np.minimum(y, h - 1 - y) / (h * margin)
    return smooth(0, 1, np.minimum(dx, 1)) * smooth(0, 1, np.minimum(dy, 1))


def save(name, rgb, alpha):
    os.makedirs(OUT, exist_ok=True)
    a = np.clip(alpha, 0, 1)
    img = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"), optimize=True)
    print("wrote", name, "coverage %.2f" % a.mean())


def damp_rising():
    h, w = 512, 1024
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    top = 0.3 + 0.22 * noise(1, w, 1.5, 1)[0][None, :] + 0.12 * noise(1, w, 1.0, 2)[0][None, :]
    height = 1 - y  # 1 at the bottom of the image
    body = smooth(top - 0.02, top - 0.25, 1 - height)  # inside the damp zone
    inside = 1 - smooth(-0.05, 0.0, height - top)
    tide = np.exp(-((height - top) / 0.012) ** 2)
    mott = noise(h, w, 2.0, 3)
    alpha = (inside * (0.35 + 0.35 * mott) * (0.5 + 0.5 * (1 - height)) + tide * 0.55)
    alpha *= border(h, w, 0.12) * smooth(0.0, 0.08, 1 - y + 0.08)
    col = np.dstack([0.36 + 0.06 * mott, 0.31 + 0.05 * mott, 0.24 + 0.03 * mott])
    col = col * (1 - tide[..., None] * 0.3)
    save("damp_rising", col, alpha * 0.9)


def water_streak():
    h, w = 1024, 256
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    rng = np.random.default_rng(11)
    alpha = np.zeros((h, w))
    # a dozen runs of different width, length and strength, slightly wandering
    for i in range(12):
        cx = rng.uniform(0.15, 0.85)
        width = rng.uniform(0.01, 0.05)
        length = rng.uniform(0.3, 0.95)
        strength = rng.uniform(0.25, 0.8)
        wander = (noise(h, 1, 2.0, 100 + i)[:, 0][:, None] - 0.5) * 0.06
        d = np.abs(x - cx - wander) / width
        run = np.exp(-d * d) * smooth(length, length * 0.6, y) * strength
        alpha = np.maximum(alpha, run)
    head = smooth(0.0, 0.05, y)  # soft start under the sill
    alpha *= head * (0.7 + 0.3 * noise(h, w, 2.0, 12)) * border(h, w, 0.06)
    col = np.dstack([0.3 + 0 * alpha, 0.28 + 0 * alpha, 0.24 + 0 * alpha])
    save("water_streak", col, alpha * 0.85)


def grime_smudge():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n - 0.5
    r = np.sqrt(x * x + y * y)
    blot = noise(n, n, 1.8, 21)
    prints = smooth(0.62, 0.7, noise(n, n, 1.2, 22))
    alpha = smooth(0.48, 0.15, r + (blot - 0.5) * 0.25) * (0.35 + 0.4 * blot + 0.25 * prints)
    col = np.dstack([0.2 + 0.05 * blot, 0.18 + 0.04 * blot, 0.15 + 0.03 * blot])
    save("grime_smudge", col, alpha * 0.75)


def ceiling_stain():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n - 0.5
    warp = noise(n, n, 2.2, 31) - 0.5
    r = np.sqrt(x * x + y * y) + warp * 0.12
    rings = 0
    for k, rad in enumerate((0.38, 0.31, 0.22)):
        rings = rings + np.exp(-((r - rad) / 0.008) ** 2) * (0.7 - k * 0.15)
    fill = smooth(0.4, 0.3, r) * (0.18 + 0.12 * noise(n, n, 2.0, 32))
    alpha = np.clip(fill + rings * 0.6, 0, 1) * smooth(0.5, 0.42, r)
    col = np.dstack([0.42 + 0 * r, 0.33 + 0 * r, 0.2 + 0 * r])
    save("ceiling_stain", col, alpha)


def floor_dirt():
    """Symmetric about its long centre line: the map centres it on the foot of
    a wall, so the half under the wall is hidden and the visible half fades
    from the skirting out into the room (orientation-proof)."""
    h, w = 512, 1024
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    d = np.abs(y - 0.5) * 2  # 0 on the centre line, 1 at the long edges
    reach = 0.35 + 0.35 * noise(1, w, 1.3, 41)[0][None, :]
    grit = noise(h, w, 0.9, 42)
    clumps = smooth(0.6, 0.8, noise(h, w, 2.2, 43))
    alpha = smooth(reach, 0.0, d) * (0.45 + 0.35 * grit) + clumps * smooth(reach + 0.1, 0, d) * 0.3
    alpha *= border(h, w, 0.1)
    col = np.dstack([0.24 + 0.06 * grit, 0.21 + 0.05 * grit, 0.17 + 0.04 * grit])
    save("floor_dirt", col, alpha * 0.85)


def main():
    for fn in (damp_rising, water_streak, grime_smudge, ceiling_stain, floor_dirt):
        fn()


if __name__ == "__main__":
    main()
