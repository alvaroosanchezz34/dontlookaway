"""
Light study renderer for DON'T LOOK AWAY (approximation, NOT Roblox's renderer).

Reads the JSON written by tools/light_study.luau (one room of the real
procedurally built map) and ray-casts it with a simple, consistent light model,
so lighting changes can be compared before / after and NORMAL vs BLACKOUT:

  * surfaces: Lambert, albedo = part colour (linear) x mean of the colour map
    its material / MaterialVariant renders with (same textures the game uses)
  * lights: Roblox-like windowed falloff inside Range, (1 - (d/R)^2)^2,
    spot / surface cones with a soft edge; lights with Shadows cast them,
    lights without shadows pass through walls (as in Roblox)
  * ambient added flat, exposure 2^EV, ACES filmic tonemap, grade contrast /
    saturation / tint from the preset
  * no textures, no bounce light, no bloom: absolute brightness in Studio will
    differ; the comparison between states and versions is what this is for

Usage:
    python3 tools/light_study.py build/light_G_r.json out.png [state ...]
    states: NORMAL (default), EMERGENCY, BLACKOUT
"""

import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

TEX = {  # linear mean of the colour maps (assets/textures/*_color.png)
    ("Plaster", ""): 0.67, ("Plaster", "DLA_Wallpaper"): 0.60, ("Plaster", "DLA_PeelingPaint"): 0.55,
    ("Plaster", "DLA_CeilingTile"): 0.74, ("Carpet", ""): 0.46, ("CeramicTiles", ""): 0.69,
    ("Concrete", ""): 0.52, ("Concrete", "DLA_WetConcrete"): 0.44, ("WoodPlanks", ""): 0.35,
    ("Wood", ""): 0.44, ("Brick", ""): 0.40, ("Marble", ""): 0.67, ("Metal", ""): 0.66,
    ("Metal", "DLA_Hardware"): 0.47, ("Fabric", ""): 0.58, ("CorrodedMetal", ""): 0.11,
    ("Marble", "DLA_MarbleTiles"): 0.371, ("Plaster", "DLA_WallpaperAged"): 0.591,
}
EMERGENCY_COLOR = (255, 176, 120)
ALARM_COLOR = (255, 64, 52)


def lin(c):
    c = np.asarray(c, dtype=float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * x ** (1 / 2.4) - 0.055)


def aces(x):
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip((x * (a * x + b)) / (x * (c * x + d) + e), 0, 1)


def load(path):
    data = json.load(open(path))
    P = data["parts"]
    n = len(P)
    pos = np.array([p["pos"] for p in P])
    R = np.stack([np.array([p["rx"] for p in P]), np.array([p["ry"] for p in P]), np.array([p["rz"] for p in P])], axis=1)  # n,3(axis),3
    half = np.array([p["size"] for p in P]) / 2
    for i, p in enumerate(P):
        if p["shape"] == "cyl":
            half[i, 1:] *= 0.85
        elif p["shape"] == "ball":
            half[i] *= 0.8
    alb = np.zeros((n, 3))
    emit = np.zeros(n, dtype=bool)
    glass = np.zeros(n, dtype=bool)
    for i, p in enumerate(P):
        t = TEX.get((p["material"], p["variant"]), TEX.get((p["material"], ""), 0.7))
        alb[i] = lin(p["color"]) * t
        emit[i] = p["material"] == "Neon"
        glass[i] = p["material"] == "Glass" or p["transparency"] > 0.4
    return data, pos, R, half, alb, emit, glass


def intersect(orig, dirs, pos, R, half, skip=None, tmax=None):
    """Nearest hit of rays (m,3) against oriented boxes. Returns t, index, local normal axis/sign."""
    m = dirs.shape[0]
    best_t = np.full(m, np.inf)
    best_i = np.full(m, -1)
    best_n = np.zeros((m, 3))
    o = orig if orig.ndim == 2 else np.broadcast_to(orig, (m, 3))
    for i in range(pos.shape[0]):
        if skip is not None and skip[i]:
            continue
        Ri = R[i]
        lo_ = (o - pos[i]) @ Ri.T  # local origin
        ld = dirs @ Ri.T
        with np.errstate(divide="ignore", invalid="ignore"):
            inv = 1.0 / np.where(np.abs(ld) < 1e-9, 1e-9, ld)
            t1 = (-half[i] - lo_) * inv
            t2 = (half[i] - lo_) * inv
        tn = np.minimum(t1, t2)
        tf = np.maximum(t1, t2)
        tnear = tn.max(axis=1)
        tfar = tf.min(axis=1)
        hit = (tnear <= tfar) & (tfar > 1e-3)
        t = np.where(tnear > 1e-3, tnear, tfar)
        hit &= t < best_t
        if tmax is not None:
            hit &= t < tmax
        if hit.any():
            axis = np.argmax(tn, axis=1)
            sign = -np.sign(ld[np.arange(m), axis])
            nl = np.zeros((m, 3))
            nl[np.arange(m), axis] = sign
            nw = nl @ Ri
            best_t = np.where(hit, t, best_t)
            best_i = np.where(hit, i, best_i)
            best_n = np.where(hit[:, None], nw, best_n)
    return best_t, best_i, best_n


def occluded(pts, lpos, pos, R, half, skip):
    d = lpos - pts
    dist = np.linalg.norm(d, axis=1)
    dirs = d / np.maximum(dist, 1e-6)[:, None]
    t, idx, _ = intersect(pts + dirs * 0.05, dirs, pos, R, half, skip=skip, tmax=None)
    return t < dist - 0.3


def state_lights(data, state):
    out = []
    for L in data["lights"]:
        col = np.array(L["color"], dtype=float)
        b = L["brightness"]
        if L["tag"] == "fixture":
            if L["mode"] == "dead":
                continue
            emergency = L["circuit"] == "EMERGENCY"
            if state == "NORMAL":
                pass
            elif state == "EMERGENCY":
                if not emergency:
                    continue
                col, b = np.array(EMERGENCY_COLOR, float), b * 0.55
            elif state == "BLACKOUT":
                if not emergency:
                    continue
                col, b = np.array(ALARM_COLOR, float), b * 0.5 * 0.85 * 0.5  # half of them survive on average
        elif L["tag"] == "off":
            continue
        elif L["powered"] and state != "NORMAL":
            continue
        out.append(dict(L, color=col, brightness=b))
    return out


def shade(data, state, eye, target, w, h, fov, pos, R, half, alb, emit, glass, shadows=True):
    presets = data["presets"]
    preset = presets.get(state) or presets[{"NORMAL": "POWERED", "EMERGENCY": "DARK"}.get(state, state)]
    fwd = np.array(target) - np.array(eye)
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    tanh = math.tan(math.radians(fov) / 2)
    ys, xs = np.mgrid[0:h, 0:w]
    u = (xs + 0.5) / w * 2 - 1
    v = 1 - (ys + 0.5) / h * 2
    dirs = fwd[None, :] + u.reshape(-1, 1) * right * tanh * w / h + v.reshape(-1, 1) * up * tanh
    dirs /= np.linalg.norm(dirs, axis=1)[:, None]
    eye = np.array(eye, float)
    t, idx, nrm = intersect(eye, dirs, pos, R, half, skip=glass)
    hitm = idx >= 0
    pts = eye + dirs * np.where(hitm, t, 0)[:, None]
    E = np.zeros((dirs.shape[0], 3))
    amb = lin(preset["ambient"])
    lights = state_lights(data, state)
    for L in lights:
        lp = np.array(L["pos"], float)
        d = lp - pts
        dist = np.linalg.norm(d, axis=1)
        ldir = d / np.maximum(dist, 1e-6)[:, None]
        ndl = np.clip((nrm * ldir).sum(1), 0, 1)
        att = np.clip(1 - (dist / L["range"]) ** 2, 0, 1) ** 2
        k = att * ndl * L["brightness"]
        if L["class"] in ("SpotLight", "SurfaceLight"):
            ax = np.array(L["dir"], float)
            cosang = (-ldir * ax).sum(1)
            halfa = math.radians(min(L["angle"], 179) / 2)
            cone = np.clip((cosang - math.cos(min(halfa + 0.12, math.pi / 2 + 0.2))) / (math.cos(max(halfa - 0.08, 0)) - math.cos(min(halfa + 0.12, math.pi / 2 + 0.2)) + 1e-6), 0, 1)
            k *= cone
        live = hitm & (k > 1e-4)
        if shadows and L["shadows"] and live.any():
            sub = np.where(live)[0]
            occ = occluded(pts[sub], lp, pos, R, half, glass | emit)
            kk = k.copy()
            kk[sub[occ]] = 0
            k = kk
        E += k[:, None] * lin(L["color"])[None, :]
    col = np.zeros((dirs.shape[0], 3))
    a = alb[np.where(hitm, idx, 0)]
    col = a * (E + amb[None, :])
    em = hitm & emit[np.where(hitm, idx, 0)]
    if em.any():
        # emissive (Neon) parts: use their colour bright; dead lamps are Glass in game
        col[em] = alb[idx[em]] / 0.7 * 2.2
    col *= 2 ** preset["exposure"]
    disp = aces(col)
    # grade: contrast around mid grey, saturation, tint
    disp = (disp - 0.5) * (1 + preset["contrast"]) + 0.5 + preset["brightness"]
    lum = (disp * [0.2126, 0.7152, 0.0722]).sum(1, keepdims=True)
    disp = lum + (disp - lum) * (1 + preset["saturation"])
    disp *= np.array(preset["tint"]) / 255.0
    img = srgb(np.clip(disp, 0, 1)).reshape(h, w, 3)
    stats = {
        "lights": len(lights),
        "mean": float(img.mean()),
        "black": float((img.max(axis=2) < 0.06).mean()),
        "median": float(np.median(img.mean(axis=2))),
    }
    return img, stats


def camera_for(data):
    lo, hi = np.array(data["min"]), np.array(data["max"])
    c = (lo + hi) / 2
    y = lo[1]
    sx, sz = hi[0] - lo[0], hi[2] - lo[2]
    if sx > sz * 2:  # corridor along X: look down its length
        return (lo[0] + 3, y + 5.4, c[2]), (hi[0], y + 4.2, c[2])
    if sz > sx * 2:
        return (c[0], y + 5.4, hi[2] - 3), (c[0], y + 4.2, lo[2])
    eye = (c[0] - sx * 0.1, y + 5.4, hi[2] - 2.5)
    target = (c[0], y + 4.2, lo[2] + 4)
    return eye, target


def main():
    path, out = sys.argv[1], sys.argv[2]
    states = sys.argv[3:] or ["NORMAL"]
    data, pos, R, half, alb, emit, glass = load(path)
    eye, target = camera_for(data)
    w, h = 480, 270
    tiles = []
    for st in states:
        img, stats = shade(data, st, eye, target, w, h, 72, pos, R, half, alb, emit, glass)
        print("%s %s: lights %d, mean %.3f, median %.3f, near-black %.1f%%" % (data["room"], st, stats["lights"], stats["mean"], stats["median"], stats["black"] * 100))
        im = Image.fromarray((img * 255).astype(np.uint8))
        ImageDraw.Draw(im).text((6, 6), "%s  %s  (approximation)" % (data["room"], st), fill=(255, 255, 255))
        tiles.append(im)
    sheet = Image.new("RGB", (w, h * len(tiles)))
    for i, im in enumerate(tiles):
        sheet.paste(im, (0, i * h))
    sheet.save(out)


if __name__ == "__main__":
    main()
