"""
Procedural PBR texture generator for DON'T LOOK AWAY.

Writes seamless (tileable) colour / normal / roughness maps for the building's
surfaces into assets/textures/<name>/. Everything is generated from noise and
geometry in this file: original, no external images.

Colour maps are kept fairly neutral and light because Roblox multiplies a
MaterialVariant's colour map by the part's Color: the map carries detail (wear,
stains, grain), the map's tint is set per room style in Layout.Styles.

Usage:
    python3 tools/gen_textures.py [size]      (default size 1024)
"""

import os
import sys

import numpy as np
from PIL import Image

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")


# ---------------------------------------------------------------------------
# periodic noise helpers (all tile seamlessly because they are built in the
# frequency domain or from integer-period functions)
# ---------------------------------------------------------------------------

def spectral(n, beta, seed, stretch=(1.0, 1.0)):
    """1/f^beta noise, periodic, normalised to 0..1. stretch squashes frequencies
    on one axis (streaks)."""
    rng = np.random.default_rng(seed)
    white = rng.normal(size=(n, n))
    fx = np.fft.fftfreq(n)[None, :] * stretch[0]
    fy = np.fft.fftfreq(n)[:, None] * stretch[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = np.fft.fft2(white) / (f ** beta)
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def band(n, lo, hi, seed):
    """Band-limited noise between two frequencies (cycles per tile)."""
    rng = np.random.default_rng(seed)
    white = rng.normal(size=(n, n))
    fx = np.fft.fftfreq(n, d=1.0 / n)[None, :]
    fy = np.fft.fftfreq(n, d=1.0 / n)[:, None]
    f = np.sqrt(fx * fx + fy * fy)
    mask = ((f >= lo) & (f <= hi)).astype(float)
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * mask))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def blur(img, radius):
    """Periodic box blur via FFT (keeps tiling)."""
    n = img.shape[0]
    k = np.zeros((n, n))
    r = max(1, int(radius))
    k[:r, :r] = 1
    k = np.roll(k, (-r // 2, -r // 2), axis=(0, 1))
    k /= k.sum()
    return np.real(np.fft.ifft2(np.fft.fft2(img) * np.fft.fft2(k)))


def normal_from_height(h, strength):
    """OpenGL-convention normal map (green = up), periodic gradients."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nx, ny, nz = -dx, dy, np.ones_like(h)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / length, ny / length, nz / length], axis=-1) * 0.5 + 0.5


def grid(n):
    y, x = np.mgrid[0:n, 0:n] / n
    return x, y


def tide_marks(n, seed, threshold=0.62, width=0.012):
    """Water stains: small blotches with darker rims (tide lines). Kept small
    and few so the tile never reads as a repeating pattern."""
    b = band(n, 3, 7, seed) * 0.7 + spectral(n, 2.0, seed + 100) * 0.3
    threshold = max(threshold, 0.7)
    inside = smoothstep(threshold, threshold + 0.05, b)
    rim = np.exp(-((b - threshold) / width) ** 2)
    return inside, rim


def cracks(n, seed, freq=(6, 14), width=0.018):
    """Thin branching cracks from the zero-crossings of band noise, only in a
    few small regions."""
    c = band(n, freq[0], freq[1], seed) - 0.5
    line = np.exp(-(c / (width * 0.45)) ** 2)
    gate = smoothstep(0.78, 0.9, band(n, 2, 5, seed + 1))
    return line * gate


def save(name, color, height, rough, normal_strength, metal=None):
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    c = np.clip(color, 0, 1)
    Image.fromarray((c * 255).astype(np.uint8), "RGB").save(os.path.join(folder, f"{name}_color.png"), optimize=True)
    nm = normal_from_height(height, normal_strength)
    Image.fromarray((np.clip(nm, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(folder, f"{name}_normal.png"), optimize=True)
    r = np.clip(rough, 0, 1)
    Image.fromarray((r * 255).astype(np.uint8), "L").save(os.path.join(folder, f"{name}_roughness.png"), optimize=True)
    if metal is not None:
        Image.fromarray((np.clip(metal, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(folder, f"{name}_metalness.png"), optimize=True)
    print("wrote", name)


def rgb(*v):
    return np.array(v, dtype=float)[None, None, :] / 255.0


def mix(a, b, t):
    t = t[..., None] if t.ndim == 2 else t
    return a * (1 - t) + b * t


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

def plaster_aged(n):
    """Old painted plaster: blotchy discolouration, damp streaks running down,
    tide-mark stains, hairline cracks, flaking paint."""
    base = rgb(232, 230, 220) * np.ones((n, n, 1))
    blotch = spectral(n, 2.8, 11)
    grain = spectral(n, 0.9, 12)
    streak = spectral(n, 2.0, 13, stretch=(0.08, 1.0))  # long vertical runs
    stain_in, stain_rim = tide_marks(n, 14)
    crack = cracks(n, 15)
    flake = smoothstep(0.78, 0.8, spectral(n, 2.2, 16)) * smoothstep(0.4, 0.6, grain)
    col = base * (0.93 + 0.07 * blotch[..., None])
    col = mix(col, rgb(204, 198, 176), smoothstep(0.6, 0.95, streak) * 0.35)
    col = mix(col, rgb(206, 196, 168), stain_in * 0.18)
    col = mix(col, rgb(150, 136, 108), stain_rim * 0.28)
    col = mix(col, rgb(170, 166, 156), flake * 0.6)  # bare plaster under paint
    col = mix(col, rgb(96, 92, 86), crack * 0.55)
    col *= (0.96 + 0.08 * grain)[..., None]
    h = grain * 0.35 + blotch * 0.25 - crack * 0.9 - flake * 0.5
    rough = 0.78 + 0.12 * grain - 0.1 * stain_in + 0.08 * flake
    save("plaster_aged", col, h, rough, 2.2)


def wallpaper_damask(n):
    """Faded damask wallpaper in 4 strips: quatrefoil motif on fine stripes,
    sun-faded, with lifting seams and damp stains."""
    x, y = grid(n)
    reps = 4  # motifs per tile horizontally (one per paper strip)
    u = (x * reps) % 1.0 - 0.5
    v = (y * reps) % 1.0 - 0.5
    # offset every other row of motifs (half drop)
    v2 = ((y * reps + 0.5 * (np.floor(x * reps) % 2)) % 1.0) - 0.5
    r = np.sqrt(u * u + v2 * v2)
    th = np.arctan2(v2, u)
    petal = r < 0.22 * (0.55 + 0.45 * np.abs(np.cos(2 * th))) + 0.03 * np.cos(8 * th)
    ring = np.abs(r - 0.33) < 0.012
    motif = np.clip(petal.astype(float) + ring.astype(float), 0, 1)
    motif = blur(motif, 3)
    stripes = (np.sin(x * np.pi * 2 * reps * 18) > 0.6).astype(float) * 0.25
    fade = spectral(n, 3.0, 21)
    stain_in, stain_rim = tide_marks(n, 22, threshold=0.66)
    seam = np.exp(-(((x * reps) % 1.0) / 0.004) ** 2) + np.exp(-((1 - (x * reps) % 1.0) / 0.004) ** 2)
    lift = seam * smoothstep(0.5, 0.8, spectral(n, 2.0, 23, stretch=(0.2, 1.0)))
    grain = spectral(n, 1.0, 24)
    ground = rgb(226, 220, 204)
    ink = rgb(176, 168, 150)
    col = mix(ground * np.ones((n, n, 1)), ink * np.ones((n, n, 1)), np.clip(motif + stripes, 0, 1) * (0.75 - 0.35 * fade))
    col = mix(col, rgb(214, 200, 160), fade * 0.35)  # yellowing
    col = mix(col, rgb(200, 184, 146), stain_in * 0.22)
    col = mix(col, rgb(140, 120, 88), stain_rim * 0.3)
    col = mix(col, rgb(110, 104, 94), lift * 0.5)
    col *= (0.95 + 0.08 * grain)[..., None]
    h = motif * 0.25 + grain * 0.15 + lift * 0.8 - seam * 0.3
    rough = 0.82 - motif * 0.1 + 0.08 * grain
    save("wallpaper_damask", col, h, rough, 1.6)


def carpet_worn(n):
    """Low-pile office carpet: dense fibre noise, worn traffic paths, dark stains
    and grime gathered in patches."""
    fibre = spectral(n, 0.35, 31)
    fibre2 = band(n, n // 6, n // 3, 32)
    loops = (np.sin(grid(n)[0] * np.pi * 2 * 160) * np.sin(grid(n)[1] * np.pi * 2 * 160) + 1) * 0.5
    wear = spectral(n, 2.6, 33)
    stain_in, stain_rim = tide_marks(n, 34, threshold=0.7)
    grime = spectral(n, 2.0, 35)
    base = rgb(214, 214, 214) * np.ones((n, n, 1))
    col = base * (0.72 + 0.28 * (0.5 * fibre + 0.3 * fibre2 + 0.2 * loops))[..., None]
    col = mix(col, rgb(240, 236, 226), smoothstep(0.62, 0.85, wear) * 0.25)  # flattened, lighter
    col = mix(col, rgb(120, 112, 100), stain_in * 0.3)
    col = mix(col, rgb(90, 84, 74), stain_rim * 0.2)
    col *= (0.88 + 0.12 * (1 - smoothstep(0.6, 0.9, grime)))[..., None]
    h = fibre * 0.6 + fibre2 * 0.3 + loops * 0.2 - smoothstep(0.62, 0.85, wear) * 0.3
    rough = 0.94 - 0.05 * stain_in
    save("carpet_worn", col, h, rough, 1.4)


def tiles_worn(n):
    """4 x 4 ceramic floor tiles: per-tile colour, chipped corners, dirty
    grout, a few cracked tiles, grime in the corners."""
    tiles = 4
    x, y = grid(n)
    tx, ty = x * tiles, y * tiles
    fx, fy = tx % 1.0, ty % 1.0
    ix, iy = np.floor(tx).astype(int), np.floor(ty).astype(int)
    rng = np.random.default_rng(41)
    tone = rng.uniform(0.94, 1.03, size=(tiles, tiles))[iy % tiles, ix % tiles]
    edge = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
    grout_w = 0.022
    grout = 1 - smoothstep(grout_w, grout_w + 0.012, edge)
    bevel = smoothstep(grout_w, grout_w + 0.05, edge)
    chip_noise = spectral(n, 1.6, 42)
    chips = (edge < grout_w + 0.03) & (chip_noise > 0.82)
    chips = chips.astype(float)
    crack_mask = rng.random(size=(tiles, tiles))[iy % tiles, ix % tiles] > 0.75
    crack = cracks(n, 43, freq=(8, 16), width=0.012) * crack_mask
    grime = spectral(n, 2.4, 44)
    micro = spectral(n, 0.8, 45)
    base = rgb(236, 234, 228) * np.ones((n, n, 1))
    col = base * (tone * (0.97 + 0.05 * micro))[..., None]
    col = mix(col, rgb(214, 206, 190), smoothstep(0.55, 0.9, grime) * 0.5)
    col = mix(col, rgb(92, 86, 76), grout * (0.75 + 0.25 * grime))
    col = mix(col, rgb(150, 144, 132), chips * 0.8)
    col = mix(col, rgb(70, 66, 60), crack * 0.85)
    h = bevel * 0.9 - chips * 0.4 - crack * 0.6 + micro * 0.05
    rough = 0.28 + 0.6 * grout + 0.3 * chips + 0.25 * smoothstep(0.55, 0.9, grime)
    save("tiles_worn", col, h, rough, 3.0)


def ceiling_tile(n):
    """One 4x4-stud acoustic ceiling tile: fissured mineral face, a beveled edge
    and the odd water stain."""
    x, y = grid(n)
    edge = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))
    bevel = smoothstep(0.0, 0.025, edge)
    fiss = band(n, 40, 120, 51)
    fissures = smoothstep(0.62, 0.7, fiss) * smoothstep(0.4, 0.6, spectral(n, 1.2, 52))
    pores = (band(n, 150, 260, 53) > 0.78).astype(float)
    stain_in, stain_rim = tide_marks(n, 54, threshold=0.72, width=0.01)
    sag = spectral(n, 3.4, 55)
    base = rgb(238, 236, 228) * np.ones((n, n, 1))
    col = base * (0.94 + 0.06 * sag)[..., None]
    col = mix(col, rgb(170, 166, 156), fissures * 0.7 + pores * 0.4)
    col = mix(col, rgb(214, 196, 156), stain_in * 0.3)
    col = mix(col, rgb(150, 120, 80), stain_rim * 0.45)
    col = mix(col, rgb(150, 148, 140), (1 - bevel) * 0.6)
    h = bevel * 0.6 - fissures * 0.5 - pores * 0.3 + sag * 0.2
    rough = 0.96 * np.ones((n, n))
    save("ceiling_tile", col, h, rough, 2.0)


def concrete_grimy(n):
    """Basement concrete: mottled, pitted, faint formwork joints, oily grime."""
    x, y = grid(n)
    mottle = spectral(n, 2.4, 61)
    fine = spectral(n, 0.8, 62)
    pits = (band(n, 90, 200, 63) > 0.8).astype(float) * smoothstep(0.3, 0.7, spectral(n, 2.0, 64))
    joint = np.exp(-(((y * 2) % 1.0 - 0.5) / 0.004) ** 2) * 0.6
    stain_in, stain_rim = tide_marks(n, 65, threshold=0.6)
    oil = smoothstep(0.7, 0.9, spectral(n, 2.8, 66))
    crack = cracks(n, 67, freq=(4, 10))
    base = rgb(214, 212, 206) * np.ones((n, n, 1))
    col = base * (0.84 + 0.1 * mottle + 0.06 * fine)[..., None]
    col = mix(col, rgb(120, 116, 108), pits * 0.7 + joint * 0.4)
    col = mix(col, rgb(170, 162, 146), stain_in * 0.2)
    col = mix(col, rgb(120, 114, 104), stain_rim * 0.25)
    col = mix(col, rgb(96, 92, 88), oil * 0.3 + crack * 0.5)
    h = fine * 0.3 + mottle * 0.2 - pits * 0.6 - joint * 0.4 - crack * 0.8
    rough = 0.9 - oil * 0.35 + 0.05 * fine
    save("concrete_grimy", col, h, rough, 2.4)


def wood_planks_worn(n):
    """Old floorboards: 5 long boards per tile (one butt joint each, staggered),
    strong flowing grain, a few knots, dark gaps, scuffed varnish."""
    x, y = grid(n)
    boards = 5
    by = y * boards
    iy = np.floor(by).astype(int)
    fy = by % 1.0
    rng = np.random.default_rng(71)
    tone = rng.uniform(0.78, 1.08, size=boards)[iy % boards]
    joint_at = rng.uniform(0, 1, size=boards)[iy % boards]
    fx = (x - joint_at) % 1.0  # one butt joint per board per tile
    # grain: flowing lines along the board, warped by low-frequency noise
    warp = spectral(n, 2.4, 72, stretch=(1.0, 0.25))
    rings = (y * boards * 9 + warp * 2.5 + iy * 0.37) % 1.0
    grain = smoothstep(0.0, 0.18, rings) * (1 - smoothstep(0.55, 1.0, rings))
    streaks = spectral(n, 1.0, 73, stretch=(1.0, 0.04))
    gap = np.exp(-(fy / 0.02) ** 2) + np.exp(-((1 - fy) / 0.02) ** 2)
    butt = np.exp(-(np.minimum(fx, 1 - fx) / 0.0025) ** 2)
    kx, ky = rng.uniform(0, 1, 4), rng.uniform(0, 1, 4)
    knots = np.zeros((n, n))
    for i in range(4):
        dx = np.minimum(np.abs(x - kx[i]), 1 - np.abs(x - kx[i])) * 2.0
        dy = np.minimum(np.abs(y - ky[i]), 1 - np.abs(y - ky[i])) * 5.0
        d = np.sqrt(dx * dx + dy * dy)
        knots = np.maximum(knots, np.exp(-(d / 0.03) ** 2))
    scuff = smoothstep(0.6, 0.9, spectral(n, 2.4, 74, stretch=(1.0, 0.3)))
    base = rgb(222, 208, 188) * np.ones((n, n, 1))
    col = base * (tone * (0.8 + 0.2 * streaks) * (0.78 + 0.22 * grain))[..., None]
    col = mix(col, rgb(110, 86, 62), knots * 0.85)
    col = mix(col, rgb(232, 222, 204), scuff * 0.18)
    seams = np.clip(gap + butt, 0, 1)
    col = mix(col, rgb(36, 28, 22), seams)
    h = (1 - seams) * 0.8 + grain * 0.2 + streaks * 0.1 - knots * 0.15
    rough = 0.45 + 0.3 * scuff + 0.25 * seams + 0.1 * (1 - grain)
    save("wood_planks_worn", col, h, rough, 2.2)


def brick_grimy(n):
    """Running-bond brick: 8 courses, chipped arrises, sooty streaks running
    down from the mortar, damp at the bottom of the tile."""
    x, y = grid(n)
    courses, per = 8, 4
    cy = y * courses
    iy = np.floor(cy).astype(int)
    fy = cy % 1.0
    cx = x * per + 0.5 * (iy % 2)
    ix = np.floor(cx).astype(int)
    fx = cx % 1.0
    rng = np.random.default_rng(81)
    tone = rng.uniform(0.82, 1.1, size=(courses, per + 1))[iy % courses, ix % (per + 1)]
    # distance to the brick edge in tile units (bricks are 1/4 wide, 1/8 tall)
    dist = np.minimum(np.minimum(fx, 1 - fx) / per, np.minimum(fy, 1 - fy) / courses)
    mortar = 1 - smoothstep(0.006, 0.009, dist)
    face = spectral(n, 1.2, 82)
    chips = ((mortar < 0.5) & (dist < 0.016) & (spectral(n, 1.4, 83) > 0.7)).astype(float)
    soot = smoothstep(0.5, 0.85, spectral(n, 2.0, 84, stretch=(0.1, 1.0)))  # runs down the wall
    base = rgb(226, 214, 204) * np.ones((n, n, 1))
    col = base * (tone * (0.85 + 0.15 * face))[..., None]
    col = mix(col, rgb(70, 62, 58), soot * 0.45)
    col = mix(col, rgb(170, 166, 158), mortar)
    col = mix(col, rgb(150, 132, 118), chips * 0.7)
    h = (1 - mortar) * 0.8 + face * 0.2 - chips * 0.4
    rough = 0.86 + 0.08 * mortar
    save("brick_grimy", col, h, rough, 3.0)


def marble_stained(n):
    """Polished marble with turbulent veins, dulled and stained where people walked."""
    x, y = grid(n)
    turb = spectral(n, 2.2, 91) * 6 + spectral(n, 1.6, 92) * 2
    veins = np.abs(np.sin((x * 2 + y * 1) * np.pi * 2 + turb * 1.3))
    veins = 1 - smoothstep(0.0, 0.08, veins)
    fine_veins = 1 - smoothstep(0.0, 0.04, np.abs(np.sin((x * 7 - y * 5) * np.pi * 2 + turb * 1.7)))
    cloud = spectral(n, 2.6, 93)
    dull = smoothstep(0.55, 0.85, spectral(n, 2.4, 94))
    stain_in, stain_rim = tide_marks(n, 95, threshold=0.72)
    base = rgb(236, 236, 232) * np.ones((n, n, 1))
    col = base * (0.86 + 0.14 * cloud)[..., None]
    col = mix(col, rgb(140, 142, 138), veins * 0.55 + fine_veins * 0.25)
    col = mix(col, rgb(206, 198, 180), stain_in * 0.18)
    col = mix(col, rgb(160, 150, 130), stain_rim * 0.22)
    h = cloud * 0.05 - veins * 0.05
    rough = 0.12 + 0.35 * dull + 0.2 * stain_in
    save("marble_stained", col, h, rough, 1.0)


def metal_worn(n):
    """Painted steel: chipped paint showing rusty metal, scratches, grime."""
    x, y = grid(n)
    chips = smoothstep(0.8, 0.83, band(n, 6, 18, 101) * 0.6 + spectral(n, 1.6, 106) * 0.4)
    rust = smoothstep(0.4, 0.8, spectral(n, 1.4, 102)) * chips
    scratches = (np.abs(band(n, 60, 140, 103) - 0.5) < 0.006).astype(float) * smoothstep(0.6, 0.8, spectral(n, 2.0, 104))
    grime = spectral(n, 2.6, 105)
    base = rgb(222, 222, 220) * np.ones((n, n, 1))
    col = base * (0.9 + 0.1 * grime)[..., None]
    col = mix(col, rgb(150, 150, 152), chips)
    col = mix(col, rgb(130, 80, 50), rust * 0.85)
    col = mix(col, rgb(240, 240, 238), scratches * 0.6)
    h = (1 - chips) * 0.4 - rust * 0.2 - scratches * 0.3
    rough = 0.55 - chips * 0.2 + rust * 0.4 + 0.1 * grime
    metal = chips * (1 - rust)
    save("metal_worn", col, h, rough, 1.6, metal)


def main():
    for fn in (plaster_aged, wallpaper_damask, carpet_worn, tiles_worn, ceiling_tile, concrete_grimy, wood_planks_worn, brick_grimy, marble_stained, metal_worn):
        fn(SIZE)


if __name__ == "__main__":
    main()
