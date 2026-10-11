"""
Light probe for DON'T LOOK AWAY: fixed points measured in every building state.

Reads the JSON written by tools/light_probe.luau and, with the light model of
tools/light_study.py (Roblox-like windowed falloff, cones, shadows only from
lights that cast them, flat ambient, exposure, ACES, the preset's grade),
prints for each probe point and state the brightness a mid-grey floor shows
on screen (0 = black, 1 = white), and the mean / near-black share of two
views. An approximation: compare states and versions, not absolute values.

Usage:
    python3 tools/light_probe.py build/light_probe.json [--views] [--markdown]
"""

import json
import sys
import os

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import light_study as ls  # noqa: E402

STATES = ["NORMAL", "B1", "B2", "B3", "B4", "EMERGENCY"]
FLOOR_ALBEDO = 0.21  # linear mid grey (sRGB ~0.5)


def state_lights_for(data, state, exclude=()):
    out = []
    for L in data["lights"]:
        s = L["states"][state]
        if not s["on"] or s["brightness"] <= 0:
            continue
        if L.get("room") in exclude:
            continue
        out.append(dict(L, color=np.array(s["color"], float), brightness=s["brightness"]))
    return out


def grade(col, preset):
    col = col * 2 ** preset["exposure"]
    # graded on the display image, as ColorCorrection does
    disp = ls.srgb(ls.aces(col))
    disp = (disp - 0.5) * (1 + preset["contrast"]) + 0.5 + preset["brightness"]
    lum = (disp * [0.2126, 0.7152, 0.0722]).sum(-1, keepdims=True)
    disp = lum + (disp - lum) * (1 + preset["saturation"])
    disp = disp * np.array(preset["tint"]) / 255.0
    return np.clip(disp, 0, 1)


_skip = {}


def geo_skip(data, glass, emit):
    """Parts that cast no shadow: glass, glowing parts and CastShadow = false."""
    key = id(data)
    if key not in _skip:
        no_cast = np.array([p.get("castShadow", True) is False for p in data["parts"]])
        _skip[key] = glass | emit | no_cast
    return _skip[key]


def probe_value(data, geo, state, probe):
    pos, R, half, alb, emit, glass = geo
    preset = data["presets"][data["statePresets"][state]]
    pt = np.array([probe["pos"]], float)
    nrm = np.array([[0.0, 1.0, 0.0]])
    E = np.zeros(3)
    for L in state_lights_for(data, state, set(probe.get("exclude", []))):
        lp = np.array(L["pos"], float)
        d = lp - pt[0]
        dist = np.linalg.norm(d)
        if dist >= L["range"]:
            continue
        ldir = d / max(dist, 1e-6)
        ndl = max(0.0, float(nrm[0] @ ldir))
        k = (1 - (dist / L["range"]) ** 2) ** 2 * ndl * L["brightness"]
        if L["class"] in ("SpotLight", "SurfaceLight"):
            ax = np.array(L["dir"], float)
            cosang = float((-ldir) @ ax)
            halfa = np.radians(min(L["angle"], 179) / 2)
            outer = np.cos(min(halfa + 0.12, np.pi / 2 + 0.2))
            inner = np.cos(max(halfa - 0.08, 0))
            k *= float(np.clip((cosang - outer) / (inner - outer + 1e-6), 0, 1))
        if k <= 1e-5:
            continue
        if L["shadows"] and ls.occluded(pt, lp, pos, R, half, geo_skip(data, glass, emit))[0]:
            continue
        E += k * ls.lin(L["color"])
    amb = ls.lin(preset["ambient"])
    col = FLOOR_ALBEDO * (E + amb)
    disp = grade(col[None, :], preset)[0]
    lum = lambda c: float((np.asarray(c) * [0.2126, 0.7152, 0.0722]).sum())  # noqa: E731
    return lum(disp), lum(E) * 1000


def main():
    path = sys.argv[1]
    views = "--views" in sys.argv
    md = "--markdown" in sys.argv
    data = json.load(open(path))
    _, pos, R, half, alb, emit, glass = ls.load(path)
    geo = (pos, R, half, alb, emit, glass)
    rows = []
    for probe in data["probes"]:
        rows.append((probe["name"], [probe_value(data, geo, st, probe) for st in STATES]))
    # two tables: what a mid-grey floor shows on screen (after exposure, tone
    # map and grade), and the light arriving from the lamps (x1000, no ambient)
    for title, k, fmt in (("on screen (0-1)", 0, "%.3f"), ("light arriving x1000", 1, "%.1f")):
        if md:
            print("\n**%s**\n" % title)
            print("| Punto | " + " | ".join(STATES) + " |")
            print("|---|" + "---|" * len(STATES))
            for name, vals in rows:
                print("| %s | %s |" % (name, " | ".join(fmt % v[k] for v in vals)))
        else:
            print("\n%s" % title)
            print("%-55s %s" % ("probe", " ".join("%9s" % s for s in STATES)))
            for name, vals in rows:
                print("%-55s %s" % (name, " ".join(("%9" + fmt[1:]) % v[k] for v in vals)))
    if views:
        # the renderer reads lights through state_lights(data, state): serve ours
        ls.state_lights = lambda d, st: state_lights_for(d, st)
        for st in STATES:
            data["presets"][st] = data["presets"][data["statePresets"][st]]
        for v in data["views"]:
            means = []
            for st in STATES:
                img, stats = ls.shade(data, st, v["eye"], v["target"], 160, 90, 72, pos, R, half, alb, emit, glass)
                means.append("%s mean %.3f black %.0f%%" % (st, stats["mean"], stats["black"] * 100))
            print("view %s: %s" % (v["name"], "; ".join(means)))


if __name__ == "__main__":
    main()
