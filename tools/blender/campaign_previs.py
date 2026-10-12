"""
Campaign previs: renders the key frames exported by the client test
(CAMPAIGN_PREVIS=<dir>) as vertical 9:16 frames and lays them out per video.

    CAMPAIGN_PREVIS=build/previs lune run tools/client_test.luau build/test.rbxlx
    /home/user/.venv-blender/bin/python tools/blender/campaign_previs.py build/previs [samples]

For every <scene>_<time>.json it runs render_room.py (Cycles, 540x960) and
then applies the scene's colour grade the way Roblox's ColorCorrectionEffect
does (brightness, contrast, saturation, tint), so the frame matches the
graded picture. Every frame is stamped PREVIS: it is NOT a Roblox capture
(no Roblox renderer, no UI text, no SurfaceGuis, no post-processing other
than the grade). It shows composition, scale and light, nothing more.

Writes <dir>/<scene>_<time>.png and <dir>/sheet_<scene>.png.
"""

import glob
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
W, H = 540, 960


def grade(img, g):
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    a = a + g.get("brightness", 0)
    a = (a - 0.5) * (1 + g.get("contrast", 0)) + 0.5
    lum = (a * np.array([0.299, 0.587, 0.114], dtype=np.float32)).sum(axis=2, keepdims=True)
    a = lum + (a - lum) * (1 + g.get("saturation", 0))
    a = a * (np.array(g.get("tint", [255, 255, 255]), dtype=np.float32) / 255.0)
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def stamp(img, label):
    d = ImageDraw.Draw(img)
    d.rectangle((0, H - 34, W, H), fill=(0, 0, 0))
    d.text((10, H - 30), "PREVIS (Blender) - not a Roblox capture", fill=(220, 60, 52), font=font(13))
    d.text((10, H - 15), label, fill=(200, 200, 200), font=font(11))
    return img


def main():
    folder = sys.argv[1]
    samples = sys.argv[2] if len(sys.argv) > 2 else "32"
    env = dict(os.environ, RENDER_RES="%dx%d" % (W, H), RENDER_SAMPLES=samples)
    frames = {}
    for path in sorted(glob.glob(os.path.join(folder, "*.json"))):
        base = os.path.splitext(os.path.basename(path))[0]
        scene, t = base.rsplit("_", 1)
        out = os.path.join(folder, base + ".png")
        raw = os.path.join(folder, base + ".raw.png")
        subprocess.run([PY, os.path.join(HERE, "render_room.py"), path, raw, "meshes", "SHOT"], check=True, env=env, stdout=subprocess.DEVNULL)
        data = json.load(open(path))
        img = grade(Image.open(raw), data.get("grade") or {})
        stamp(img, "%s  @ %ss" % (scene.replace("Scene_", ""), t))
        img.save(out)
        os.remove(raw)
        frames.setdefault(scene, []).append(out)
        print("rendered", out)
    for scene, outs in frames.items():
        sheet = Image.new("RGB", (W * len(outs) + 8 * (len(outs) - 1), H), (40, 40, 40))
        for i, f in enumerate(outs):
            sheet.paste(Image.open(f), (i * (W + 8), 0))
        p = os.path.join(folder, "sheet_%s.png" % scene)
        sheet.save(p)
        print("sheet", p)


if __name__ == "__main__":
    main()
