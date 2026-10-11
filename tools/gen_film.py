"""
Film textures for DON'T LOOK AWAY's old-camera look (FilmController).

Writes to assets/film/:
  grain_light.png   512x512, seamless: white grain on transparent (the grain
                    that lifts the image)
  grain_dark.png    512x512, seamless: black grain on transparent (the grain
                    that sinks it)

Gaussian, slightly clumped grain (two octaves) like fast film stock, with its
mean at mid grey: half the pixels go to the light layer, half to the dark
one, with an alpha that grows with the distance from grey. Tiled and moved
to a random offset 24 times a second it reads as fresh grain every frame.
Dust and scratches need no texture (FilmController draws them).

Upload both (tools/upload_assets.py) and put the Image ids in
src/shared/Config/AssetIds.luau -> AssetIds.Film. While they are 0 the game
makes its grain at runtime (EditableImage) or goes without.

Usage:
    python3 tools/gen_film.py [seed]
"""

import os
import sys

import numpy as np
from PIL import Image

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "film")


def seamless_noise(rng, size, blur):
    """Gaussian noise, blurred with a wrap-around kernel (tiles without seams)."""
    n = rng.standard_normal((size, size))
    if blur <= 0:
        return n
    f = np.fft.fft2(n)
    ky = np.fft.fftfreq(size)[:, None]
    kx = np.fft.fftfreq(size)[None, :]
    g = np.exp(-(kx ** 2 + ky ** 2) * (2 * np.pi * blur) ** 2 / 2)
    out = np.real(np.fft.ifft2(f * g))
    return out / out.std()


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1337
    rng = np.random.default_rng(seed)
    os.makedirs(OUT, exist_ok=True)
    # fine grain plus a little clumping, like a fast film stock
    grain = 0.75 * seamless_noise(rng, SIZE, 0.0) + 0.45 * seamless_noise(rng, SIZE, 1.2)
    grain /= grain.std()
    strength = np.clip(np.abs(grain) / 2.6, 0, 1)
    alpha = (strength ** 0.8 * 255).astype(np.uint8)
    light = np.zeros((SIZE, SIZE, 4), np.uint8)
    dark = np.zeros((SIZE, SIZE, 4), np.uint8)
    light[..., :3] = 255
    light[..., 3] = np.where(grain > 0, alpha, 0)
    dark[..., 3] = np.where(grain < 0, alpha, 0)
    Image.fromarray(light, "RGBA").save(os.path.join(OUT, "grain_light.png"), optimize=True)
    Image.fromarray(dark, "RGBA").save(os.path.join(OUT, "grain_dark.png"), optimize=True)
    print("wrote grain_light.png, grain_dark.png (%dx%d) to %s" % (SIZE, SIZE, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
