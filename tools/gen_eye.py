"""
Generates THE EYE for Marketing Studio: original, procedural, photographic
layers (no external images). Writes assets/marketing/eye/*.png:

    eye_sclera.png   1024x512  the eyeball: wet off-white, veins, caruncle, shading
    eye_iris.png      512x512  iris: radial fibres, crypts, collarette, limbal ring
    eye_pupil.png     256x256  pupil: soft-edged black disc (scaled to dilate)
    eye_glint.png     512x512  corneal reflection + wet sheen (moves with the iris)
    eye_lid_top.png  1024x512  upper lid for blinking (skin + lash line)
    eye_lid_bot.png  1024x512  lower lid for blinking
    eye_socket.png   1024x512  skin around the eye with an almond hole: the mask
                               that frames everything, lids' shadow, lashes, waterline
    eye_preview.png            composites (open / looking aside / half shut)

Layer order in the game (back to front): sclera, iris, pupil, glint, lids, socket.

    python3 tools/gen_eye.py
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "marketing", "eye")
W, H = 1024, 512
CX, CY = 512, 262
X0, X1 = 118, 906  # eye corners
TOP_H, BOT_H = 168, 112
IRIS_D = 336  # iris diameter on the 1024 canvas
rng = np.random.default_rng(1987)


# ------------------------------------------------------------------ helpers

def value_noise(shape, scale, octaves=4, seed=0):
    """Smooth fractal value noise in [0, 1]."""
    g = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        s = max(1, int(scale * (2 ** o)))
        grid = g.random((s + 2, s + 2)).astype(np.float32)
        img = Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += amp * (np.asarray(img, np.float32) / 255.0)
        total += amp
        amp *= 0.5
    return out / total


def blur(arr, radius):
    if arr.ndim == 2:
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))
        return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255.0
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), np.float32)


def lid_curves(x):
    """Upper and lower lid edge y for canvas x (almond, inner corner lower)."""
    t = np.clip((x - X0) / (X1 - X0), 0, 1)
    tilt = (t - 0.5) * -14  # outer corner slightly higher
    peak = np.clip(np.sin(np.pi * np.clip(t ** 0.9, 0, 1)), 0, 1)
    top = CY - TOP_H * peak ** 0.8 + tilt
    bot = CY + BOT_H * np.clip(np.sin(np.pi * t), 0, 1) ** 1.15 + tilt * 0.4
    return top, bot


def almond_mask(soft=2.0, grow=0.0):
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    top, bot = lid_curves(xs[0])
    top = top[None, :] - grow
    bot = bot[None, :] + grow
    inside = (ys > top) & (ys < bot) & (xs > X0 - grow) & (xs < X1 + grow)
    m = inside.astype(np.float32)
    return blur(m, soft) if soft > 0 else m


def save(arr_rgba, name):
    Image.fromarray(np.clip(arr_rgba, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))


# ------------------------------------------------------------------ sclera

def sclera():
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    base = np.array([216, 208, 192], np.float32)
    n = value_noise((H, W), 6, 5, 11)
    col = np.ones((H, W, 3), np.float32) * base
    col *= (0.94 + 0.08 * n)[..., None]
    # spherical shading: the ball turns away towards the corners and up under the lid
    dx = (xs - CX) / (X1 - X0) * 2
    dy = (ys - CY) / (TOP_H + BOT_H) * 2
    r2 = dx ** 2 * 0.9 + dy ** 2 * 0.7
    shade = np.clip(1.0 - 0.7 * r2 ** 1.2, 0.2, 1.0)
    col *= shade[..., None]
    # warm-pink tint growing towards both corners (bloodshot, tired)
    corner = np.clip(np.abs(dx) ** 2.2, 0, 1)
    col = col * (1 - 0.35 * corner[..., None]) + np.array([178, 96, 92]) * 0.35 * corner[..., None]
    # caruncle: the pink flesh at the inner corner
    cd = np.sqrt(((xs - (X0 + 40)) / 46) ** 2 + ((ys - (CY + 6)) / 34) ** 2)
    car = np.clip(1.2 - cd, 0, 1) ** 1.5
    caro = np.array([170, 88, 86]) * (0.8 + 0.3 * value_noise((H, W), 30, 2, 5))[..., None]
    col = col * (1 - car[..., None]) + caro * car[..., None]
    # veins: thin branching random walks from the corners, deep red, blurred
    veins = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(veins)
    for side in (-1, 1):
        for _ in range(30):
            x = CX + side * rng.uniform(190, 390)
            y = CY + rng.uniform(-120, 110)
            ang = math.atan2(CY - y, CX - x) + rng.uniform(-0.6, 0.6)
            width = rng.uniform(1.6, 3.2)
            length = rng.uniform(80, 230)
            steps = int(length / 4)
            stack = [(x, y, ang, width, steps)]
            while stack:
                x, y, ang, width, steps = stack.pop()
                for i in range(steps):
                    nx = x + math.cos(ang) * 4
                    ny = y + math.sin(ang) * 4
                    d.line([(x, y), (nx, ny)], fill=int(150 + 100 * (width / 3.2)), width=max(1, int(round(width))))
                    x, y = nx, ny
                    ang += rng.normal(0, 0.18)
                    width *= 0.985
                    if rng.random() < 0.05 and width > 0.9:
                        stack.append((x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.4, 0.9), width * 0.6, int(steps * 0.5)))
    v = np.asarray(veins.filter(ImageFilter.GaussianBlur(0.9)), np.float32) / 255.0
    v *= np.clip(np.abs(dx) * 1.6, 0.3, 1.0)  # stronger in the corners, faint near the iris
    vein_col = np.array([150, 36, 38], np.float32)
    col = col * (1 - 0.75 * v[..., None]) + vein_col * 0.75 * v[..., None]
    a = np.full((H, W), 255, np.float32)
    save(np.dstack([col, a]), "eye_sclera.png")
    return col


# ------------------------------------------------------------------ iris

def iris():
    S = 512
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    c = (S - 1) / 2
    dx, dy = xs - c, ys - c
    r = np.sqrt(dx ** 2 + dy ** 2) / (S / 2 - 6)  # 0 centre, 1 edge
    th = np.arctan2(dy, dx)
    # radial fibres: high-frequency noise along the angle, slowly warped with r
    def angular(freq, seed, warp):
        g = np.random.default_rng(seed)
        k = g.random(freq).astype(np.float32)
        t = (th / (2 * np.pi) + 0.5) * freq + warp * np.sin(r * 9 + seed) + 0.6 * r
        i0 = np.floor(t).astype(int) % freq
        i1 = (i0 + 1) % freq
        f = t - np.floor(t)
        f = f * f * (3 - 2 * f)
        return k[i0] * (1 - f) + k[i1] * f
    fib = 0.5 * angular(180, 1, 0.5) + 0.3 * angular(420, 2, 0.8) + 0.2 * angular(900, 3, 1.1)
    # crypts: dark lacunae between collarette and edge
    crypt = value_noise((S, S), 16, 3, 21)
    crypt = np.clip((crypt - 0.62) * 7, 0, 1) * np.clip((r - 0.44) / 0.06, 0, 1) * np.clip((0.84 - r) / 0.08, 0, 1)
    stroma = np.clip((angular(260, 7, 0.9) - 0.72) * 4, 0, 1) * np.clip((r - 0.45) / 0.2, 0, 1) * np.clip((0.86 - r) / 0.1, 0, 1)
    # colours: hazel ring around the pupil, cold grey-green outward
    inner = np.array([118, 108, 92], np.float32)
    mid = np.array([112, 114, 112], np.float32)
    outer = np.array([82, 86, 88], np.float32)
    t1 = np.clip((r - 0.22) / 0.25, 0, 1)[..., None]
    t2 = np.clip((r - 0.5) / 0.4, 0, 1)[..., None]
    col = inner * (1 - t1) + mid * t1
    col = col * (1 - t2) + outer * t2
    col *= (0.62 + 0.75 * fib)[..., None]
    col = col * (1 - 0.6 * crypt[..., None]) + np.array([46, 36, 28]) * 0.6 * crypt[..., None]
    col = col + np.array([70, 74, 66]) * (0.35 * stroma)[..., None]
    # collarette: a wavy brighter ring
    wave = 0.4 + 0.035 * np.sin(th * 13) + 0.02 * np.sin(th * 29 + 1)
    coll = np.exp(-((r - wave) / 0.03) ** 2)
    col = col + np.array([40, 36, 30]) * coll[..., None] * 0.7
    # contraction furrows
    for rr in (0.62, 0.72, 0.81):
        f = np.exp(-((r - rr - 0.01 * np.sin(th * 7)) / 0.012) ** 2)
        col *= (1 - 0.08 * f)[..., None]
    # limbal ring: dark, soft outer border
    limb = np.clip((r - 0.8) / 0.18, 0, 1) ** 1.4
    col *= (1 - 0.82 * limb)[..., None]
    # shading: the cornea's dome darkens the top (lid shadow handled by the socket)
    col *= (0.9 + 0.12 * (dy / c * -0.5 + 0.5))[..., None]
    alpha = np.clip((1.0 - r) / 0.025, 0, 1) * 255
    save(np.dstack([col, alpha]), "eye_iris.png")
    return col, alpha


def pupil():
    S = 256
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    c = (S - 1) / 2
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2) / (S / 2 - 2)
    alpha = np.clip((1.0 - r) / 0.12, 0, 1) * 255
    col = np.zeros((S, S, 3), np.float32) + np.array([6, 6, 8])
    save(np.dstack([col, alpha]), "eye_pupil.png")


def glint():
    S = 512
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    c = (S - 1) / 2
    a = np.zeros((S, S), np.float32)
    # the light source reflected on the curved cornea: an elongated, slightly
    # bent soft highlight up-left, with a sharp hot core
    ang = -0.6
    ux = (xs - (c - 105)) * math.cos(ang) - (ys - (c - 118)) * math.sin(ang)
    uy = (xs - (c - 105)) * math.sin(ang) + (ys - (c - 118)) * math.cos(ang)
    uy = uy + (ux / 60) ** 2 * 6
    a += np.exp(-((ux / 46) ** 2 + (uy / 17) ** 2) * 2.2) * 0.85
    a += np.exp(-(((xs - (c - 112)) / 9) ** 2 + ((ys - (c - 122)) / 7) ** 2)) * 0.9
    # a faint secondary reflection low-right (the floor)
    a += np.exp(-(((xs - (c + 120)) / 34) ** 2 + ((ys - (c + 120)) / 12) ** 2)) * 0.18
    # broad wet sheen across the cornea
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2) / c
    a += np.clip(1 - r, 0, 1) ** 2 * 0.06
    a = blur(np.clip(a, 0, 1), 1.6)
    col = np.zeros((S, S, 3), np.float32) + np.array([255, 252, 246])
    save(np.dstack([col, a * 255]), "eye_glint.png")


# ------------------------------------------------------------------ skin, lids, socket

def skin_texture(seed):
    base = np.array([78, 58, 52], np.float32)
    n1 = value_noise((H, W), 40, 3, seed)  # pores
    n2 = value_noise((H, W), 5, 4, seed + 1)  # blotches
    col = np.ones((H, W, 3), np.float32) * base
    col *= (0.8 + 0.25 * n2)[..., None]
    col *= (0.93 + 0.1 * n1)[..., None]
    return col


def lash_layer(edge_fn, upper, count, ss=3):
    """Real-looking lashes: tapered quadratic strands in small clumps, drawn at
    `ss`x and downsampled (anti-aliased). edge_fn(x) -> lid edge y."""
    layer = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    out = -1 if upper else 1
    i = 0
    while i < count:
        clump = int(rng.integers(2, 5))
        t0 = rng.uniform(0.04, 0.97)
        base_lean = (t0 - 0.42) * (1.5 if upper else 1.0)
        for _ in range(clump):
            t = np.clip(t0 + rng.normal(0, 0.006), 0.02, 0.98)
            x = X0 + t * (X1 - X0)
            y = edge_fn(x) - out * 2
            prof = 0.45 + 0.75 * math.sin(math.pi * min(1.0, t * 1.15))  # longer towards the outer corner
            length = (rng.uniform(32, 60) if upper else rng.uniform(10, 22)) * prof
            lean = base_lean + rng.normal(0, 0.08)
            # quadratic bezier: out of the lid, then curling up and outward
            p0 = (x, y)
            p1 = (x + lean * length * 0.2, y + out * length * 0.85)
            curl = length * (0.45 if upper else 0.1)
            p2 = (x + lean * length * 1.05 + math.copysign(curl * 0.3, lean), y + out * length * 0.55 - out * curl * 0.15 + (-curl * 0.35 if upper else 0))
            steps = 14
            pts = []
            for k in range(steps + 1):
                s = k / steps
                bx = (1 - s) ** 2 * p0[0] + 2 * (1 - s) * s * p1[0] + s * s * p2[0]
                by = (1 - s) ** 2 * p0[1] + 2 * (1 - s) * s * p1[1] + s * s * p2[1]
                pts.append((bx * ss, by * ss))
            w0 = (2.6 if upper else 1.5) * ss
            for k in range(steps):
                s = k / steps
                w = max(1, int(round(w0 * (1 - s) ** 0.8)))
                alpha = int((230 if upper else 170) * (1 - 0.6 * s))
                d.line([pts[k], pts[k + 1]], fill=(10, 8, 7, alpha), width=w)
            i += 1
    return layer.resize((W, H), Image.LANCZOS)


def lashes(img, upper):
    def edge(x):
        top, bot = lid_curves(np.array([x]))
        return float((top if upper else bot)[0])
    img.alpha_composite(lash_layer(edge, upper, 120 if upper else 60))


def socket():
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    col = skin_texture(31)
    # orbital shading: fades into black away from the eye (the scene is a black card)
    dx = (xs - CX) / 560
    dy = (ys - CY) / 300
    fall = np.clip(1.15 - np.sqrt(dx ** 2 + dy ** 2), 0, 1) ** 1.6
    col *= fall[..., None]
    # upper lid crease and the fold above it
    top, bot = lid_curves(xs[0])
    crease = np.exp(-((ys - (top[None, :] - 48)) / 9) ** 2) * ((xs > X0 + 30) & (xs < X1 - 30))
    col *= (1 - 0.45 * crease)[..., None]
    span = np.clip(1 - np.abs(xs - CX) / ((X1 - X0) / 2 + 60), 0, 1) ** 0.6
    above = np.clip((top[None, :] - ys) / 60, 0, 1)
    fold = np.exp(-((ys - (top[None, :] - 22)) / 18) ** 2) * span
    col *= (1 + 0.18 * fold)[..., None]  # the lid's rounded skin catches light
    col *= (1 - 0.12 * above * span)[..., None]
    # lower lid: a rounded roll of skin under the lashes, then a tired groove
    span_l = np.clip(1 - np.abs(xs - CX) / ((X1 - X0) / 2 + 30), 0, 1) ** 0.5
    roll = np.exp(-((ys - (bot[None, :] + 11)) / 8) ** 2) * span_l
    groove = np.exp(-((ys - (bot[None, :] + 40)) / 15) ** 2) * span_l
    col *= (1 + 0.28 * roll - 0.4 * groove)[..., None]
    col = col * (1 - 0.18 * groove[..., None]) + np.array([62, 42, 56]) * 0.18 * groove[..., None]
    # upper lid margin catches light right above the lashes
    margin = np.exp(-((top[None, :] - 7 - ys) / 6) ** 2) * span_l
    col *= (1 + 0.25 * margin)[..., None]
    # wet waterline: a thin pink rim just outside the opening
    hole = almond_mask(1.2)
    rim = np.clip(almond_mask(1.5, grow=4) - hole, 0, 1)
    lower = (ys > CY).astype(np.float32)
    rim *= 0.25 + 0.4 * lower
    col = col * (1 - rim[..., None]) + np.array([150, 92, 88]) * rim[..., None]
    # alpha: opaque skin, transparent eye opening, with a soft dark lid shadow
    # cast on the eyeball just inside the opening (deeper under the upper lid)
    inside_top = np.clip((ys - top[None, :]) / 46, 0, 1)
    inside_bot = np.clip((bot[None, :] - ys) / 26, 0, 1)
    shadow = np.clip(1 - np.minimum(inside_top * 1.0, inside_bot * 1.6), 0, 1) ** 1.5 * 0.78
    corners = np.clip(np.abs(xs - CX) / ((X1 - X0) / 2) - 0.72, 0, 1) * 1.6
    shadow = np.clip(shadow + corners * 0.55, 0, 0.92)
    alpha = (1 - hole) + hole * shadow
    # lash line: the dense root of the lashes darkens the lid margin
    band_top = np.exp(-((top[None, :] - 3 - ys) / 3.5) ** 2) * (ys < top[None, :] + 1) * span_l
    band_bot = np.exp(-((ys - bot[None, :] - 2) / 1.8) ** 2) * (ys > bot[None, :] - 1) * span_l
    dark = np.clip(band_top * 0.92 + band_bot * 0.55, 0, 1)
    col = col * (1 - dark[..., None]) + np.array([12, 9, 8]) * dark[..., None]
    rgb_shadow = np.zeros_like(col)
    out = col * (1 - hole[..., None]) + rgb_shadow * hole[..., None]
    img = Image.fromarray(np.dstack([np.clip(out, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8), "RGBA")
    lashes(img, True)
    lashes(img, False)
    img.save(os.path.join(OUT, "eye_socket.png"))
    return img


def lid(upper):
    """A lid that slides over the eye to blink. Edge follows the almond."""
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    col = skin_texture(41 if upper else 51)
    top, bot = lid_curves(xs[0])
    # the closed lid edge sits on the middle line between both lids
    if upper:
        edge = (top + bot) / 2 + 6
        a = np.clip((edge[None, :] - ys) / 2.5, 0, 1)
        sh = np.clip((edge[None, :] - ys) / 70, 0, 1)
    else:
        edge = (top + bot) / 2 - 6
        a = np.clip((ys - edge[None, :]) / 2.5, 0, 1)
        sh = np.clip((ys - edge[None, :]) / 50, 0, 1)
    col *= (0.45 + 0.75 * sh * (1 - sh) * 2.2 + 0.2 * sh)[..., None]  # a rounded lid: lit in the middle, dark at the edge
    # a moist highlight along the lid margin
    margin = np.exp(-((ys - (edge[None, :] - (3 if upper else -3))) / 2.2) ** 2) * ((xs > X0) & (xs < X1))
    col = col + np.array([90, 70, 66]) * (0.5 * margin)[..., None]
    img = Image.fromarray(np.dstack([np.clip(col, 0, 255), np.clip(a * 255, 0, 255)]).astype(np.uint8), "RGBA")
    # lashes along the closing edge (pointing down when shut)
    # lashes always hang away from the eye: down from both lid edges when shut
    if upper:
        img.alpha_composite(lash_layer(lambda x: float(edge[int(np.clip(x, 0, W - 1))]), False, 90))
    img.save(os.path.join(OUT, "eye_lid_top.png" if upper else "eye_lid_bot.png"))


# ------------------------------------------------------------------ preview

def composite(look=(0.0, 0.0), pupil_scale=0.42, close=0.0):
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    canvas.alpha_composite(Image.open(os.path.join(OUT, "eye_sclera.png")))
    iris_img = Image.open(os.path.join(OUT, "eye_iris.png")).resize((IRIS_D, IRIS_D), Image.LANCZOS)
    ix = int(CX - IRIS_D / 2 + look[0] * 190)
    iy = int(CY - IRIS_D / 2 - 6 + look[1] * 60)
    canvas.alpha_composite(iris_img, (ix, iy))
    p = int(IRIS_D * pupil_scale)
    canvas.alpha_composite(Image.open(os.path.join(OUT, "eye_pupil.png")).resize((p, p), Image.LANCZOS), (ix + (IRIS_D - p) // 2, iy + (IRIS_D - p) // 2))
    canvas.alpha_composite(Image.open(os.path.join(OUT, "eye_glint.png")).resize((IRIS_D, IRIS_D), Image.LANCZOS), (ix, iy))
    if close > 0:
        top = Image.open(os.path.join(OUT, "eye_lid_top.png"))
        bot = Image.open(os.path.join(OUT, "eye_lid_bot.png"))
        canvas.alpha_composite(top, (0, int(-H * 0.5 * (1 - close))))
        canvas.alpha_composite(bot, (0, int(H * 0.3 * (1 - close * 0.25))))
    canvas.alpha_composite(Image.open(os.path.join(OUT, "eye_socket.png")))
    return canvas


def main():
    os.makedirs(OUT, exist_ok=True)
    sclera()
    iris()
    pupil()
    glint()
    lid(True)
    lid(False)
    socket()
    a = composite()
    b = composite(look=(0.55, 0.15), pupil_scale=0.3)
    c = composite(close=0.6)
    sheet = Image.new("RGBA", (W, H * 3), (0, 0, 0, 255))
    for i, im in enumerate((a, b, c)):
        sheet.alpha_composite(im, (0, H * i))
    sheet.convert("RGB").save(os.path.join(OUT, "eye_preview.png"))
    print("eye layers written to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
