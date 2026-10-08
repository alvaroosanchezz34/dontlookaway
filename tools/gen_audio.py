"""
Procedural audio for DON'T LOOK AWAY: every sound is synthesised here from
oscillators, noise, filters, envelopes and a convolution reverb. No samples, no
external audio: original by construction.

Sounds are packed into three "sheets" (one audio file each, so only three
uploads are needed). The game plays a sound by enabling PlaybackRegion on the
sheet: see src/shared/Config/AudioSheets.luau (written by this script).

    assets/audio/dla_ambience.ogg   loops (rooms, weather, machines, music pads)
    assets/audio/dla_horror.ogg     The Observer, scares, the building, anomalies
    assets/audio/dla_world.ogg      footsteps, doors, devices, interactions

Usage:
    python3 tools/gen_audio.py            (needs numpy + ffmpeg with libvorbis)
"""

import json
import math
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "audio")
SHEETS_LUAU = os.path.join(ROOT, "src", "shared", "Config", "AudioSheets.luau")
GAP = 0.35  # silence between sounds on a sheet

rng = np.random.default_rng(1994)


# ---------------------------------------------------------------------------
# building blocks
# ---------------------------------------------------------------------------

def n_of(sec):
    return max(1, int(sec * SR))


def t_of(sec):
    return np.arange(n_of(sec)) / SR


def noise(sec):
    return rng.standard_normal(n_of(sec))


def osc(freq, sec, shape="sine", phase=0.0):
    """freq: number or per-sample array (sweeps)."""
    n = n_of(sec)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, float)[:n]
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if shape == "sine":
        return np.sin(ph)
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
    raise ValueError(shape)


def sweep(f0, f1, sec, curve="exp"):
    t = np.linspace(0, 1, n_of(sec))
    if curve == "exp":
        return f0 * (f1 / f0) ** t
    return f0 + (f1 - f0) * t


def spectral(x, gain_fn):
    """Zero-phase filter: multiply the spectrum by gain_fn(freqs)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * gain_fn(f), len(x))


def lp(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def hp(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bp(x, lo, hi, order=2):
    return hp(lp(x, hi, order), lo, order)


def peak(x, fc, q=8.0, gain=1.0):
    """Resonance (formant / body mode) added on top of the signal."""
    return x + gain * spectral(x, lambda f: 1 / (1 + ((f - fc) / (fc / q)) ** 2))


def reson(x, fc, q=20.0):
    """Only the resonance (a ringing body excited by x)."""
    return spectral(x, lambda f: 1 / (1 + ((f - fc) / (fc / q)) ** 2))


def stft_filter(x, mask_fn, win=2048, hop=512):
    """Time-varying filter: mask_fn(frame_time, freqs) -> gains."""
    n = len(x)
    w = np.hanning(win)
    pad = np.concatenate([np.zeros(win), x, np.zeros(win)])
    out = np.zeros_like(pad)
    norm = np.zeros_like(pad)
    f = np.fft.rfftfreq(win, 1 / SR)
    for start in range(0, len(pad) - win, hop):
        frame = pad[start:start + win] * w
        g = mask_fn((start - win) / SR, f)
        out[start:start + win] += np.fft.irfft(np.fft.rfft(frame) * g, win) * w
        norm[start:start + win] += w * w
    out /= np.maximum(norm, 1e-6)
    return out[win:win + n]


def env(sec, a=0.01, d=0.0, s=1.0, r=0.1, curve=1.0):
    n = n_of(sec)
    e = np.ones(n) * s
    na, nd, nr = n_of(a), n_of(d), n_of(r)
    e[:na] = np.linspace(0, 1, na) ** curve
    if nd > 1:
        e[na:na + nd] = np.linspace(1, s, nd)[: max(0, min(nd, n - na))]
    e[-nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def decay(sec, tau):
    return np.exp(-t_of(sec) / tau)


def fit(x, sec):
    n = n_of(sec)
    return x[:n] if len(x) >= n else np.concatenate([x, np.zeros(n - len(x))])


def add(*xs):
    """Sum signals of different lengths (padded to the longest)."""
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[: len(x)] += x
    return out


def mixat(base, x, at):
    i = n_of(at) if at > 0 else 0
    j = min(len(base), i + len(x))
    if j > i:
        base[i:j] += x[: j - i]
    return base


def reverb(x, sec=2.5, wet=0.35, damp=3500.0, pre=0.012):
    """Convolution with a synthetic room: decaying, darkening noise."""
    ir_len = n_of(sec)
    ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (SR * sec / 6.9))
    ir = lp(ir, damp, 1)
    ir = np.concatenate([np.zeros(n_of(pre)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + len(ir)
    size = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]
    out = np.concatenate([x, np.zeros(len(ir))]) * (1 - wet) + y * wet * 1.4
    return out


def drive(x, amount=3.0):
    return np.tanh(x * amount) / np.tanh(amount)


def norm(x, level=0.85):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * level


def rms_norm(x, db=-20.0):
    r = np.sqrt(np.mean(x ** 2)) + 1e-9
    y = x * (10 ** (db / 20) / r)
    m = np.max(np.abs(y))
    return y / m * 0.95 if m > 0.95 else y


def seamless(gen, sec, xfade=1.5):
    """A loop that joins without a click: generate extra, crossfade the tail
    into the head (equal power)."""
    n = n_of(sec)
    k = min(n_of(xfade), n // 2)
    x = gen(sec + k / SR + 0.01)
    if len(x) < n + k:
        x = np.concatenate([x, np.zeros(n + k - len(x))])
    head, tail = x[:k], x[n:n + k]
    a = np.linspace(0, np.pi / 2, k)
    y = x[:n].copy()
    y[:k] = head * np.sin(a) + tail * np.cos(a)
    return y


def trim_tail(x, threshold=0.0015):
    idx = np.where(np.abs(x) > threshold)[0]
    if len(idx) == 0:
        return x
    end = min(len(x), idx[-1] + n_of(0.05))
    y = x[:end].copy()
    k = min(len(y), n_of(0.03))
    y[-k:] *= np.linspace(1, 0, k)
    return y


# ---------------------------------------------------------------------------
# reusable sound recipes
# ---------------------------------------------------------------------------

def thump(f0=70, f1=38, sec=0.5, click=0.4, body=600):
    t = t_of(sec)
    tone = osc(sweep(f0, f1, sec), sec) * np.exp(-t / (sec * 0.25))
    hit = lp(noise(sec), body) * np.exp(-t / 0.02) * click
    return tone + hit


def wood_knock(f=210, sec=0.35):
    exc = noise(sec) * np.exp(-t_of(sec) / 0.003)
    body = reson(exc, f, 12) * 6 + reson(exc, f * 2.3, 14) * 3 + reson(exc, f * 4.1, 16) * 1.2
    return body * np.exp(-t_of(sec) / 0.07) + lp(exc, 3000) * 0.5


def metal_bang(f=160, sec=3.0, bright=1.0):
    t = t_of(sec)
    ratios = [1, 2.76, 5.40, 8.93, 13.3]
    out = np.zeros(n_of(sec))
    for i, r in enumerate(ratios):
        detune = 1 + rng.uniform(-0.004, 0.004)
        out += osc(f * r * detune, sec) * np.exp(-t / (sec * (0.5 / (1 + i * 0.6)))) * (0.9 ** i) * (bright if i > 1 else 1)
    out += lp(noise(sec), 4000) * np.exp(-t / 0.01) * 0.6
    return out


def creak(sec=1.2, rate0=55, rate1=18, f1=420, f2=980, jitter=0.25):
    """Stick-slip friction: an irregular impulse train through wooden body modes."""
    n = n_of(sec)
    rates = sweep(rate0, rate1, sec, "lin") * (1 + jitter * (lp(noise(sec), 6) * 6))
    phase = np.cumsum(np.maximum(rates, 2) / SR)
    imp = np.zeros(n)
    idx = np.where(np.diff(np.floor(phase)) > 0)[0]
    imp[idx] = rng.uniform(0.4, 1.0, len(idx))
    body = reson(imp, f1, 10) * 4 + reson(imp, f2, 14) * 2.5 + reson(imp, f1 * 3.3, 18)
    return body * env(sec, 0.06, 0, 1, sec * 0.3)


def breath(sec, inhale=True, f_lo=350, f_hi=2600, rough=0.0, voice=0.0):
    t = t_of(sec)
    shape = np.sin(np.pi * np.clip(t / sec, 0, 1)) ** (0.7 if inhale else 1.3)
    if inhale:
        shape *= 0.5 + 0.5 * t / sec
    x = bp(noise(sec), f_lo, f_hi)
    x = peak(x, 1100 if inhale else 700, 4, 1.5)
    if rough:
        x *= 1 + rough * np.sin(2 * np.pi * 31 * t) * lp(noise(sec), 20) * 4
    if voice:
        x += voice * drive(osc(72 + 6 * np.sin(2 * np.pi * 0.7 * t), sec, "saw"), 2) * 0.15
    return x * shape


def whisper(sec, syllables=6, seed=0):
    """Breathy noise through moving vowel formants: words you almost understand."""
    local = np.random.default_rng(seed)
    vowels = [(300, 870, 2240), (530, 1840, 2480), (660, 1720, 2410), (440, 1020, 2240), (570, 840, 2410), (270, 2290, 3010)]
    x = hp(noise(sec), 300)
    picks = [vowels[local.integers(len(vowels))] for _ in range(syllables + 1)]
    seg = sec / syllables

    def mask(time, f):
        i = min(int(time / seg), syllables - 1) if time > 0 else 0
        a = (time % seg) / seg if time > 0 else 0
        f1, f2, f3 = [picks[i][k] * (1 - a) + picks[i + 1][k] * a for k in range(3)]
        g = 0.05 + 1 / (1 + ((f - f1) / 90) ** 2) + 0.8 / (1 + ((f - f2) / 130) ** 2) + 0.4 / (1 + ((f - f3) / 200) ** 2)
        return g + 0.25 * (f > 4000) * (f < 8000)

    y = stft_filter(x, mask)
    t = t_of(sec)
    syll = np.clip(np.sin(np.pi * ((t / seg) % 1.0)), 0, 1) ** 0.6
    gaps = (local.random(syllables) > 0.15).astype(float)
    syll *= gaps[np.minimum((t / seg).astype(int), syllables - 1)]
    return y * syll * env(sec, 0.05, 0, 1, 0.2)


def fm(carrier, ratio, index, sec, vib=0.0, vib_rate=6.0):
    t = t_of(sec)
    c = np.asarray(carrier, float) if not np.isscalar(carrier) else np.full(n_of(sec), float(carrier))
    c = c * (1 + vib * np.sin(2 * np.pi * vib_rate * t))
    mod = osc(c * ratio, sec) * index
    ph = 2 * np.pi * np.cumsum(c) / SR + mod
    return np.sin(ph)


def bell(f, sec, partials=((1, 1), (2.0, 0.5), (2.76, 0.4), (5.4, 0.25), (8.9, 0.1))):
    t = t_of(sec)
    out = np.zeros(n_of(sec))
    for r, a in partials:
        out += osc(f * r, sec) * a * np.exp(-t / (sec * 0.35 / r ** 0.5))
    return out * env(sec, 0.002, 0, 1, 0.05)


def step(material, seed):
    """One footstep: heel + toe, coloured by the surface."""
    local = np.random.default_rng(seed)
    sec = 0.4
    out = np.zeros(n_of(sec))
    for at, amp in ((0.0, 1.0), (0.055 + local.uniform(0, 0.02), 0.6)):
        exc = noise(0.12) * np.exp(-t_of(0.12) / (0.004 if material != "carpet" else 0.012))
        if material == "concrete":
            s = lp(exc, 2500) + reson(exc, 140, 6) * 2
        elif material == "tile":
            s = hp(exc, 600) * 1.2 + reson(exc, 2400, 10) * 1.5 + reson(exc, 180, 6)
        elif material == "wood":
            s = reson(exc, 180, 8) * 4 + reson(exc, 420, 10) * 2 + lp(exc, 1800) * 0.5
        elif material == "metal":
            s = reson(exc, 520, 30) * 3 + reson(exc, 1430, 40) * 2 + reson(exc, 2950, 50) + hp(exc, 1500) * 0.4
        else:  # carpet
            s = lp(exc, 700) * 1.5
        mixat(out, s * amp, at)
    return out


# ---------------------------------------------------------------------------
# AMBIENCE (loops)
# ---------------------------------------------------------------------------

def amb_drone(sec=30):
    def g(s):
        t = t_of(s)
        x = np.zeros(n_of(s))
        for f, a in ((41.2, 1), (41.6, 0.8), (55.0, 0.5), (61.7, 0.35), (82.4, 0.2), (110.2, 0.08)):
            x += osc(f, s) * a * (0.7 + 0.3 * np.sin(2 * np.pi * (0.03 + f / 9000) * t + f))
        dust = bp(noise(s), 80, 420) * (0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.045 * t)))
        return x * 0.6 + dust * 0.5
    return rms_norm(reverb(seamless(g, sec), 5, 0.4, 900)[: n_of(sec)], -18)


def amb_air(sec=20):
    def g(s):
        t = t_of(s)
        x = lp(noise(s), 700) + bp(noise(s), 1800, 4000) * 0.04
        return x * (0.75 + 0.25 * np.sin(2 * np.pi * 0.07 * t) * np.sin(2 * np.pi * 0.023 * t))
    return rms_norm(seamless(g, sec), -22)


def amb_hum(sec=10):
    def g(s):
        x = np.zeros(n_of(s))
        for k in range(1, 12):
            x += osc(50 * k * (1 + rng.uniform(-0.0005, 0.0005)), s) * (0.9 ** k) * (1.6 if k == 2 else 1)
        return x + lp(noise(s), 500) * 0.15
    return rms_norm(seamless(g, sec, 0.5), -22)


def amb_rain(sec=20):
    def g(s):
        x = bp(noise(s), 400, 7000) * 0.35 + lp(noise(s), 160) * 0.5
        n = n_of(s)
        drops = np.zeros(n)
        for _ in range(int(s * 160)):
            i = rng.integers(0, n - 2000)
            f = rng.uniform(1500, 5000)
            d = osc(sweep(f, f * 1.6, 0.03), 0.03) * np.exp(-t_of(0.03) / 0.006) * rng.uniform(0.05, 0.4)
            drops[i:i + len(d)] += d
        return x + drops
    return rms_norm(reverb(seamless(g, sec), 1.5, 0.2, 5000)[: n_of(sec)], -20)


def amb_wind(sec=20):
    def g(s):
        x = noise(s)
        gust = lambda tt: 0.5 + 0.5 * np.sin(2 * np.pi * 0.06 * tt + 1.3) * np.sin(2 * np.pi * 0.11 * tt)
        y = stft_filter(x, lambda tt, f: (1 / (1 + ((f - (250 + 600 * gust(tt))) / (120 + 200 * gust(tt))) ** 2)) * (0.3 + gust(tt)))
        whistle = osc(sweep(820, 760, s, "lin"), s) * 0.02 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * t_of(s)))
        return y + whistle
    return rms_norm(seamless(g, sec, 3), -20)


def amb_vent(sec=15):
    def g(s):
        t = t_of(s)
        x = lp(noise(s), 420) + osc(118, s) * 0.08 + osc(236, s) * 0.03
        rattle = bp(noise(s), 900, 2400) * 0.06 * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 0.31 * t)))
        return x + rattle
    return rms_norm(seamless(g, sec), -21)


def amb_buzz(sec=8):
    def g(s):
        t = t_of(s)
        base = drive(osc(100, s, "square") * 0.6 + osc(200, s) * 0.3, 2)
        x = bp(base, 90, 4000) * (0.85 + 0.15 * lp(noise(s), 4) * 8)
        crackle = (rng.random(n_of(s)) > 0.9994).astype(float) * rng.uniform(-1, 1, n_of(s))
        return x + hp(np.convolve(crackle, np.exp(-np.arange(80) / 12), "same"), 1500) * 3
    return rms_norm(seamless(g, sec, 0.5), -21)


def amb_boiler(sec=12):
    def g(s):
        t = t_of(s)
        x = lp(noise(s), 90) * 2 + osc(36, s) * 0.3 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t))
        thud = np.zeros(n_of(s))
        for at in np.arange(0.4, s, 2.0):
            mixat(thud, thump(60, 35, 0.6, 0.2, 300) * 0.5, at)
        return x + thud
    return rms_norm(seamless(g, sec), -18)


def amb_fans(sec=10):
    def g(s):
        x = bp(noise(s), 200, 3500) * 0.5
        for k in range(1, 6):
            x += osc(183 * k, s) * 0.05 / k
        return x
    return rms_norm(seamless(g, sec), -21)


def amb_static(sec=6):
    def g(s):
        x = bp(noise(s), 300, 6000)
        crack = (rng.random(n_of(s)) > 0.998) * rng.uniform(-6, 6, n_of(s))
        return x * (0.7 + 0.3 * lp(noise(s), 8) * 10) + crack
    return rms_norm(seamless(g, sec, 0.3), -20)


def amb_alarm(sec=4.8):
    t = t_of(sec)
    f = np.where((t % 1.2) < 0.6, 660, 550)
    x = lp(osc(f, sec, "tri") + 0.3 * osc(f * 2, sec, "tri"), 2500)
    gate = np.clip(np.sin(np.pi * ((t % 0.6) / 0.6)) * 3, 0, 1)
    return rms_norm(reverb(x * gate, 1.2, 0.25, 4000)[: n_of(sec)], -20)


def amb_observer_breath(sec=6):
    x = np.zeros(n_of(sec))
    mixat(x, breath(2.4, True, 250, 2200, rough=0.5, voice=0.8), 0.1)
    mixat(x, breath(3.2, False, 180, 1500, rough=0.8, voice=1.2), 2.6)
    return norm(lp(x, 3000), 0.8)


def amb_closet_breath(sec=4):
    x = np.zeros(n_of(sec))
    for c in range(2):
        mixat(x, breath(0.8, True, 300, 1800), c * 2.0)
        mixat(x, breath(1.0, False, 250, 1400), c * 2.0 + 0.85)
    return norm(lp(x, 900), 0.8)


def amb_tape(sec=6):
    def g(s):
        t = t_of(s)
        hiss = hp(noise(s), 2500) * 0.25
        hum = osc(50 * (1 + 0.004 * np.sin(2 * np.pi * 0.7 * t)), s) * 0.08
        return hiss + hum
    return rms_norm(seamless(g, sec, 0.5), -22)


def amb_water(sec=10):
    def g(s):
        x = lp(noise(s), 1400) * 0.6
        n = n_of(s)
        for _ in range(int(s * 9)):
            i = rng.integers(0, n - 9000)
            f = rng.uniform(250, 700)
            b = osc(sweep(f, f * 2.2, 0.08), 0.08) * np.sin(np.pi * np.linspace(0, 1, n_of(0.08))) * rng.uniform(0.1, 0.4)
            x[i:i + len(b)] += b
        return x
    return rms_norm(seamless(g, sec), -20)


def amb_power_hum(sec=6):
    def g(s):
        x = np.zeros(n_of(s))
        for k, a in ((1, 0.5), (2, 1.0), (3, 0.4), (4, 0.3), (6, 0.15), (8, 0.08)):
            x += osc(60 * k, s) * a
        return drive(x * 0.5, 1.5) + lp(noise(s), 300) * 0.05
    return rms_norm(seamless(g, sec, 0.5), -22)


def amb_fridge(sec=8):
    def g(s):
        t = t_of(s)
        return (osc(48, s) + 0.5 * osc(96, s) + 0.2 * osc(144, s)) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.2 * t)) + lp(noise(s), 400) * 0.1
    return rms_norm(seamless(g, sec, 0.5), -24)


def amb_thermal(sec=4):
    def g(s):
        return osc(6800, s) * 0.03 + osc(310, s) * 0.2 + osc(620, s) * 0.06 + hp(noise(s), 4000) * 0.02
    return rms_norm(seamless(g, sec, 0.3), -26)


def amb_steam(sec=6):
    def g(s):
        t = t_of(s)
        return hp(noise(s), 1600) * (0.7 + 0.3 * lp(noise(s), 3) * 10) * (0.9 + 0.1 * np.sin(2 * np.pi * 0.4 * t))
    return rms_norm(seamless(g, sec, 0.5), -22)


def amb_phone(sec=6):
    x = np.zeros(n_of(sec))
    for start in (0.0, 0.0):
        ring = (bell(1000, 2.0) + bell(1210, 2.0)) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 20 * t_of(2.0))))
        mixat(x, ring * env(2.0, 0.01, 0, 1, 0.1), start)
    return norm(reverb(x, 1.0, 0.2, 5000)[: n_of(sec)], 0.8)


def amb_music_pad(sec=24):
    def g(s):
        t = t_of(s)
        x = np.zeros(n_of(s))
        # a cold cluster: root, minor second, tritone, a high glassy fifth
        for f, a in ((65.4, 1), (69.3, 0.6), (92.5, 0.45), (196.0, 0.15), (293.7, 0.06)):
            for d in (-0.3, 0.3):
                x += osc(f + d * 0.4 * np.sin(2 * np.pi * 0.05 * t + f), s, "saw") * a
        return lp(x, 700)
    return rms_norm(reverb(seamless(g, sec, 3), 6, 0.5, 2000)[: n_of(sec)], -20)


def amb_chase_pad(sec=13.714):
    beat = 60 / 140
    def g(s):
        t = t_of(s)
        note = np.where((t % (beat * 8)) < beat * 4, 55.0, 58.3)
        x = drive(osc(note, s, "saw") + osc(note * 1.005, s, "saw"), 2.5)
        pulse = (1 - (t % (beat / 2)) / (beat / 2)) ** 3
        return lp(x, 900) * (0.4 + 0.6 * pulse)
    x = g(sec)
    k = n_of(0.02)
    x[:k] *= np.linspace(0, 1, k)
    x[-k:] *= np.linspace(1, 0, k)
    return rms_norm(x, -18)


# ---------------------------------------------------------------------------
# HORROR (one-shots)
# ---------------------------------------------------------------------------

def h_observer_step():
    x = add(thump(55, 30, 0.9, 0.5, 450), creak(0.5, 70, 30, 260, 640) * 0.15)
    return reverb(x, 1.6, 0.3, 1800)


def h_observer_inhale():
    x = breath(1.7, True, 220, 2600, rough=1.0, voice=1.0)
    return reverb(x, 0.8, 0.15, 3000)


def h_observer_screech():
    sec = 1.9
    t = t_of(sec)
    car = sweep(780, 1450, sec, "exp") * (1 + 0.03 * np.sin(2 * np.pi * 7.5 * t))
    x = fm(car, 1.41, 3.5 + 3 * t / sec, sec) + 0.6 * fm(car * 1.33, 2.01, 5, sec)
    x = drive(x * 0.8, 1.7) + hp(noise(sec), 2500) * 0.12
    x *= env(sec, 0.04, 0, 1, 0.6)
    return reverb(x, 1.8, 0.3, 4500)


def h_observer_impact():
    sec = 1.6
    t = t_of(sec)
    sub = osc(sweep(130, 32, sec), sec) * np.exp(-t / 0.4) * 1.4
    crash = lp(noise(sec), 5000) * np.exp(-t / 0.08)
    clang = metal_bang(97, sec, 1.2) * 0.4
    x = drive(add(sub, crash, clang), 2.5)
    return reverb(x, 2.2, 0.3, 3000)


def h_observer_crack():
    x = np.zeros(n_of(0.6))
    for i, at in enumerate((0.0, 0.05, 0.08, 0.15, 0.17)):
        c = hp(noise(0.03), 1200) * np.exp(-t_of(0.03) / 0.003) * (1 - i * 0.12)
        mixat(x, c, at)
    mixat(x, thump(140, 80, 0.15, 0.3, 800) * 0.6, 0.0)
    return reverb(x, 0.6, 0.15, 5000)


def h_observer_twitch():
    x = np.zeros(n_of(0.4))
    mixat(x, hp(noise(0.02), 900) * np.exp(-t_of(0.02) / 0.002), 0)
    mixat(x, bp(noise(0.25), 400, 2000) * np.exp(-t_of(0.25) / 0.05) * 0.4 * (np.sin(2 * np.pi * 40 * t_of(0.25)) > 0), 0.02)
    return x


def h_observer_appear():
    sec = 2.2
    t = t_of(sec)
    swell = stft_filter(noise(sec), lambda tt, f: 1 / (1 + (f / (300 + 5000 * (tt / sec) ** 2)) ** 4)) * (t / sec) ** 3
    x = swell
    mixat(x, thump(60, 28, 1.2, 0.6, 400) * 1.5, sec - 0.25)
    return reverb(fit(x, sec + 1.0), 2.5, 0.35, 2500)


def h_observer_vanish():
    sec = 1.6
    t = t_of(sec)
    x = stft_filter(noise(sec), lambda tt, f: 1 / (1 + (f / (4000 * (1 - tt / sec) + 150)) ** 4)) * np.exp(-t / 0.5)
    return reverb(x, 2.0, 0.4, 3000)


def h_observer_sting():
    sec = 2.2
    t = t_of(sec)
    x = np.zeros(n_of(sec))
    for f in (110, 116.5, 155.6, 220, 233.1, 311.1):
        x += osc(f * (1 + rng.uniform(-0.003, 0.003)), sec, "saw")
    x = lp(x, 2600) * np.exp(-t / 0.7) + lp(noise(sec), 6000) * np.exp(-t / 0.05) * 3
    return reverb(drive(x * 0.3, 2), 2.8, 0.35, 3500)


def h_observer_hunt():
    sec = 4.0
    t = t_of(sec)
    x = drive(osc(sweep(38, 76, sec), sec, "saw") + osc(sweep(38.5, 77, sec), sec, "saw") * 0.8, 2.5)
    x = stft_filter(x, lambda tt, f: 1 / np.sqrt(1 + (f / (400 + 1800 * (max(tt, 0) / sec) ** 2)) ** 4)) * env(sec, 0.5, 0, 1, 0.8)
    return reverb(x, 3.0, 0.35, 2000)


def h_observer_rush():
    sec = 0.9
    t = t_of(sec)
    x = stft_filter(noise(sec), lambda tt, f: 1 / (1 + ((f - (300 + 3000 * tt / sec)) / 800) ** 2)) * (t / sec) ** 1.5
    return reverb(x * env(sec, 0.01, 0, 1, 0.05), 0.8, 0.2, 4000)


def h_whisper_name():
    return reverb(whisper(2.0, 4, 11) * 1.5, 2.5, 0.45, 3500)


def h_jump_sting():
    sec = 1.6
    t = t_of(sec)
    shriek = fm(sweep(1200, 1900, sec), 1.5, 6, sec, 0.02, 9) * env(sec, 0.005, 0, 1, 0.9)
    stab = lp(noise(sec), 7000) * np.exp(-t / 0.04) * 2
    low = osc(sweep(90, 40, sec), sec) * np.exp(-t / 0.3)
    return reverb(drive(shriek * 0.7 + stab + low, 2.2), 1.8, 0.3, 5000)


def h_death_hit():
    sec = 3.0
    t = t_of(sec)
    x = osc(sweep(90, 24, sec), sec) * np.exp(-t / 0.8) * 1.5 + lp(noise(sec), 2500) * np.exp(-t / 0.15)
    x += metal_bang(61, sec, 0.8) * 0.5
    return reverb(drive(x, 3), 4.0, 0.4, 1800)


def h_tinnitus():
    sec = 3.5
    t = t_of(sec)
    x = osc(6200, sec) + osc(6214, sec) * 0.6
    return x * env(sec, 0.02, 0, 1, 2.5) * 0.6


def h_whisper():
    return reverb(whisper(2.6, 7, 3), 1.8, 0.35, 4000)


def h_knock_door():
    x = np.zeros(n_of(1.4))
    for at in (0.0, 0.32, 0.6):
        mixat(x, wood_knock(190 + rng.uniform(-8, 8)) * rng.uniform(0.8, 1.0), at)
    return reverb(x, 0.9, 0.2, 4000)


def h_thud():
    return reverb(thump(80, 40, 0.7, 0.8, 900), 1.2, 0.25, 2500)


def h_door_slam():
    sec = 1.2
    x = np.zeros(n_of(sec))
    mixat(x, add(thump(95, 45, 0.6, 1.2, 1600) * 1.4, fit(wood_knock(150, 0.5), 0.6) * 1.2), 0)
    rattle = bp(noise(0.5), 1500, 5000) * np.exp(-t_of(0.5) / 0.12) * (np.sin(2 * np.pi * 34 * t_of(0.5)) > 0.3) * 0.4
    mixat(x, rattle, 0.03)
    return reverb(drive(x, 1.8), 1.8, 0.3, 3500)


def h_distant_knock():
    x = np.zeros(n_of(1.2))
    for at in (0.0, 0.4):
        mixat(x, wood_knock(160), at)
    return reverb(lp(x, 1200), 3.0, 0.6, 1500)


def h_distant_pipe():
    return reverb(lp(metal_bang(210, 3.0), 2500), 3.5, 0.55, 2000)


def h_distant_metal():
    sec = 4.0
    t = t_of(sec)
    x = fm(sweep(140, 110, sec, "lin"), 2.76, 2 + np.sin(2 * np.pi * 0.6 * t), sec) * env(sec, 0.8, 0, 1, 1.5)
    return reverb(lp(x, 1500), 4.0, 0.55, 1500)


def h_distant_groan():
    return reverb(lp(creak(2.8, 25, 9, 180, 420, 0.4), 900), 3.0, 0.5, 1200)


def h_wood_creak():
    return reverb(creak(1.3, 60, 22, 430, 1000), 1.0, 0.2, 4000)


def h_elevator_groan():
    sec = 4.0
    x = add(creak(sec, 18, 8, 120, 330, 0.5), fm(70, 2.76, 1.5, sec) * 0.3 * env(sec, 1, 0, 1, 1.5))
    return reverb(lp(x, 1200), 3.5, 0.5, 1200)


def h_building_settle():
    x = creak(1.8, 30, 12, 160, 380, 0.5)
    dust = bp(noise(1.8), 2000, 8000) * np.exp(-t_of(1.8) / 0.4) * 0.05
    return reverb(add(lp(x, 1000), dust), 2.5, 0.45, 1500)


def h_stretch_groan():
    return reverb(creak(3.4, 14, 6, 110, 260, 0.6), 3.5, 0.5, 1200)


def h_falsetto():
    sec = 2.6
    t = t_of(sec)
    f = 520 * (1 + 0.012 * np.sin(2 * np.pi * 5.2 * t))
    x = osc(f, sec) + 0.3 * osc(f * 2, sec) + 0.1 * osc(f * 3, sec)
    x = peak(x, 320, 4, 2) * env(sec, 0.4, 0, 1, 0.9)
    return reverb(x, 3.0, 0.5, 3500)


def h_music_box():
    notes = [76, 79, 83, 81, 79, 76, 74, 76]  # a little minor tune
    x = np.zeros(n_of(4.4))
    for i, m in enumerate(notes):
        f = 440 * 2 ** ((m - 69) / 12) * (1 + rng.uniform(-0.006, 0.006))
        mixat(x, bell(f, 1.2, ((1, 1), (3.0, 0.3), (5.1, 0.1))) * 0.5, i * 0.42 + rng.uniform(0, 0.03))
    return reverb(x, 2.0, 0.35, 5000)


def h_reality_shift():
    sec = 1.8
    t = t_of(sec)
    x = stft_filter(noise(sec), lambda tt, f: 1 / (1 + ((f - (6000 - 5600 * tt / sec)) / 500) ** 2)) * np.sin(np.pi * t / sec)
    x += osc(sweep(400, 90, sec), sec) * np.sin(np.pi * t / sec) * 0.3
    return reverb(x, 2.5, 0.45, 4000)


def h_reality_snap():
    sec = 1.0
    x = hp(noise(0.03), 800) * np.exp(-t_of(0.03) / 0.004)
    x = fit(x, sec)
    shimmer = sum(osc(f, sec) * np.exp(-t_of(sec) / 0.25) for f in (1760, 2217, 2637)) * 0.08
    return reverb(x + shimmer, 2.0, 0.35, 6000)


def h_heartbeat(sec=0.9, gap=0.22):
    x = np.zeros(n_of(sec))
    mixat(x, thump(60, 40, 0.25, 0.15, 200), 0)
    mixat(x, thump(55, 38, 0.25, 0.1, 180) * 0.7, gap)
    return lp(x, 300)


def h_breath():
    return lp(breath(1.6, False, 300, 2400), 3500)


def h_breath_heavy():
    x = np.zeros(n_of(1.3))
    mixat(x, breath(0.45, True, 400, 3000), 0)
    mixat(x, breath(0.6, False, 350, 2600), 0.5)
    return x


def h_power_down():
    sec = 2.6
    t = t_of(sec)
    whine = osc(sweep(620, 35, sec), sec) * 0.5 + osc(sweep(1240, 70, sec), sec) * 0.2
    x = whine * np.exp(-t / 1.2)
    mixat(x, thump(90, 40, 0.6, 1.0, 1200), 0.0)
    return reverb(x, 3.0, 0.4, 2500)


def h_power_on():
    sec = 2.6
    t = t_of(sec)
    x = osc(sweep(40, 600, sec), sec) * (t / sec) * 0.4
    mixat(x, thump(110, 50, 0.5, 1.0, 1500), 0.05)
    hum = amb_power_hum(2.0)[: n_of(2.0)] * 0.3
    mixat(x, hum * np.linspace(0, 1, len(hum)), sec - 2.0)
    return reverb(x, 2.0, 0.3, 3000)


def h_electric_surge():
    sec = 1.0
    x = drive(osc(100, sec, "square"), 3) * np.exp(-t_of(sec) / 0.4)
    crack = (rng.random(n_of(sec)) > 0.995) * rng.uniform(-4, 4, n_of(sec))
    return bp(x * 0.4 + crack, 100, 7000)


def h_sparks():
    sec = 0.7
    n = n_of(sec)
    x = np.zeros(n)
    for _ in range(14):
        i = rng.integers(0, n - 800)
        x[i:i + 600] += hp(noise(600 / SR), 2000) * np.exp(-np.arange(600) / 60) * rng.uniform(0.3, 1)
    return x


def h_bulb_pop():
    x = np.zeros(n_of(0.9))
    mixat(x, hp(noise(0.05), 600) * np.exp(-t_of(0.05) / 0.006) * 1.5, 0)
    for _ in range(6):
        mixat(x, bell(rng.uniform(3000, 6500), 0.25, ((1, 1), (2.4, 0.4))) * 0.15, rng.uniform(0.02, 0.4))
    return x


def h_light_flicker():
    x = np.zeros(n_of(0.3))
    for at in (0.0, 0.07, 0.11):
        mixat(x, hp(noise(0.01), 1500) * np.exp(-t_of(0.01) / 0.002), at)
    mixat(x, amb_buzz(0.2)[: n_of(0.2)] * 0.3, 0.02)
    return x


def h_drip():
    x = osc(sweep(1100, 2400, 0.06), 0.06) * np.exp(-t_of(0.06) / 0.015)
    return reverb(fit(x, 0.3), 1.2, 0.35, 6000)


def h_exit_unlocked():
    sec = 3.0
    x = np.zeros(n_of(sec))
    mixat(x, thump(70, 35, 0.8, 1.0, 900) * 1.3, 0)
    mixat(x, metal_bang(130, 2.5, 0.7) * 0.6, 0.05)
    chord = sum(osc(f, 2.5, "tri") for f in (220, 277.2, 329.6)) * env(2.5, 0.3, 0, 1, 1.2) * 0.15
    mixat(x, chord, 0.4)
    return reverb(x, 3.5, 0.4, 2500)


def h_title_hit():
    sec = 3.0
    t = t_of(sec)
    x = osc(sweep(70, 26, sec), sec) * np.exp(-t / 0.9) * 1.4 + lp(noise(sec), 1800) * np.exp(-t / 0.2)
    return reverb(drive(x, 2), 4.5, 0.45, 1500)


def h_footsteps_behind():
    x = np.zeros(n_of(1.1))
    mixat(x, step("wood", 5), 0)
    mixat(x, step("wood", 6) * 0.85, 0.55)
    return reverb(x, 1.2, 0.3, 3500)


# ---------------------------------------------------------------------------
# WORLD (one-shots)
# ---------------------------------------------------------------------------

def w_step(material):
    return lambda: reverb(step(material, hash(material) % 1000), 0.5, 0.12, 5000)


def w_door_open():
    return reverb(add(creak(1.1, 45, 20, 380, 900), fit(wood_knock(240, 0.15) * 0.3, 1.1)), 0.9, 0.2, 4000)


def w_door_close():
    x = np.zeros(n_of(0.7))
    mixat(x, add(thump(110, 60, 0.4, 0.8, 1500), fit(wood_knock(170, 0.3), 0.4) * 0.8), 0)
    mixat(x, hp(noise(0.02), 2000) * np.exp(-t_of(0.02) / 0.003) * 0.5, 0.08)  # latch
    return reverb(x, 0.8, 0.2, 4000)


def w_door_locked():
    x = np.zeros(n_of(0.6))
    for at in (0.0, 0.12, 0.22, 0.34):
        mixat(x, add(reson(noise(0.06) * np.exp(-t_of(0.06) / 0.006), 1800, 25) * 3, hp(noise(0.02), 2500) * np.exp(-t_of(0.02) / 0.003)), at)
    return x


def w_door_unlock():
    x = np.zeros(n_of(0.45))
    mixat(x, reson(noise(0.05) * np.exp(-t_of(0.05) / 0.004), 2400, 30) * 3, 0)
    mixat(x, reson(noise(0.08) * np.exp(-t_of(0.08) / 0.006), 1500, 20) * 4, 0.15)
    return x


def w_fuse_insert():
    x = np.zeros(n_of(0.5))
    mixat(x, hp(noise(0.03), 1000) * np.exp(-t_of(0.03) / 0.004), 0)
    mixat(x, thump(180, 120, 0.15, 0.6, 2500), 0.12)
    return reverb(x, 0.6, 0.15, 5000)


def w_breaker_flip():
    x = add(thump(160, 90, 0.3, 1.2, 3500), fit(metal_bang(900, 0.3, 0.6) * 0.2, 0.3))
    return reverb(x, 0.9, 0.2, 4500)


def w_keypad(kind):
    def f():
        if kind == "beep":
            return osc(1320, 0.11) * env(0.11, 0.003, 0, 1, 0.02) * 0.6
        if kind == "error":
            return lp(osc(180, 0.45, "square"), 2000) * env(0.45, 0.005, 0, 1, 0.05) * 0.5
        x = np.zeros(n_of(0.35))
        mixat(x, osc(1046, 0.12) * env(0.12, 0.003, 0, 1, 0.02), 0)
        mixat(x, osc(1568, 0.18) * env(0.18, 0.003, 0, 1, 0.05), 0.13)
        return x * 0.6
    return f


def w_dial_turn():
    x = np.zeros(n_of(0.4))
    for i in range(5):
        mixat(x, reson(noise(0.03) * np.exp(-t_of(0.03) / 0.002), 3200, 30) * 2, i * 0.07)
    return x


def w_tape_insert():
    x = np.zeros(n_of(0.5))
    mixat(x, thump(220, 140, 0.12, 0.8, 4000), 0)
    mixat(x, thump(260, 160, 0.1, 0.8, 4000) * 0.8, 0.18)
    return x


def w_boards_break():
    sec = 1.2
    x = np.zeros(n_of(sec))
    mixat(x, thump(120, 60, 0.4, 1.5, 3000), 0)
    for _ in range(18):
        mixat(x, hp(noise(0.03), 1500) * np.exp(-t_of(0.03) / 0.004) * rng.uniform(0.2, 1), rng.uniform(0, 0.35))
    mixat(x, creak(0.5, 120, 60, 500, 1300) * 0.3, 0.02)
    return reverb(x, 1.2, 0.25, 4000)


def w_shutter_open():
    sec = 3.0
    t = t_of(sec)
    rattle = bp(noise(sec), 300, 4000) * (0.6 + 0.4 * (np.sin(2 * np.pi * 22 * t) > 0)) * env(sec, 0.2, 0, 1, 0.6)
    x = add(rattle, metal_bang(85, sec, 0.5) * 0.2)
    mixat(x, thump(80, 40, 0.6, 1, 1200), sec - 0.6)
    return reverb(x, 2.0, 0.35, 3000)


def w_paper():
    sec = 0.6
    return bp(noise(sec), 1500, 8000) * (lp(np.abs(noise(sec)), 30) * 6) * env(sec, 0.02, 0, 1, 0.15)


def w_pickup():
    x = np.zeros(n_of(0.3))
    mixat(x, hp(noise(0.04), 800) * np.exp(-t_of(0.04) / 0.008), 0)
    mixat(x, reson(noise(0.06) * np.exp(-t_of(0.06) / 0.004), 900, 12) * 2, 0.05)
    return x


def w_drop():
    return reverb(thump(220, 140, 0.25, 1.0, 3000), 0.6, 0.15, 4500)


def w_place():
    return thump(260, 180, 0.18, 0.8, 3500)


def w_switch(f=2600, sec=0.12, low=1.0):
    def g():
        x = reson(noise(sec) * np.exp(-t_of(sec) / 0.003), f, 25) * 2 + hp(noise(sec), 2000) * np.exp(-t_of(sec) / 0.002) * low
        return x
    return g


def w_flashlight_dead():
    x = np.zeros(n_of(0.5))
    mixat(x, w_switch(2000)(), 0)
    mixat(x, amb_buzz(0.3)[: n_of(0.3)] * np.linspace(0.4, 0, n_of(0.3)), 0.03)
    return x


def w_clock_tick():
    return reson(noise(0.06) * np.exp(-t_of(0.06) / 0.002), 3800, 40) * 2


def w_lock_release():
    sec = 1.5
    x = np.zeros(n_of(sec))
    mixat(x, thump(90, 45, 0.6, 1.0, 1200), 0)
    mixat(x, hp(noise(0.8), 2500) * np.exp(-t_of(0.8) / 0.25) * 0.3, 0.1)  # hiss
    return reverb(x, 1.6, 0.3, 3000)


def w_ward_break():
    sec = 1.5
    x = np.zeros(n_of(sec))
    mixat(x, hp(noise(0.05), 1200) * np.exp(-t_of(0.05) / 0.01) * 1.5, 0)
    for _ in range(22):
        mixat(x, bell(rng.uniform(2500, 7500), 0.4, ((1, 1), (2.4, 0.5))) * rng.uniform(0.05, 0.25), rng.uniform(0, 0.6))
    return reverb(x, 2.5, 0.35, 6000)


def w_escape_door():
    return w_shutter_open()


def w_death_fall():
    x = np.zeros(n_of(0.9))
    mixat(x, thump(90, 45, 0.4, 1.2, 900), 0)
    mixat(x, thump(110, 55, 0.3, 0.8, 1200) * 0.6, 0.18)
    return reverb(x, 1.0, 0.25, 3000)


def w_equip():
    x = np.zeros(n_of(0.3))
    mixat(x, w_switch(1800, 0.1)(), 0)
    mixat(x, hp(noise(0.12), 2000) * np.exp(-t_of(0.12) / 0.03) * 0.3, 0.04)
    return x


# ---------------------------------------------------------------------------
# sheets
# ---------------------------------------------------------------------------

SHEETS = {
    "ambience": [
        ("AmbientDrone", amb_drone), ("AmbientAir", amb_air), ("AmbientHum", amb_hum), ("AmbientRain", amb_rain),
        ("Wind", amb_wind), ("Ventilation", amb_vent), ("ElectricBuzz", amb_buzz), ("BoilerRumble", amb_boiler),
        ("ServerFans", amb_fans), ("Static", amb_static), ("RadioStatic", amb_static), ("EmergencyAlarm", amb_alarm),
        ("ObserverBreath", amb_observer_breath), ("BreathingCloset", amb_closet_breath), ("TapeHiss", amb_tape),
        ("WaterRush", amb_water), ("PowerHum", amb_power_hum), ("Fridge", amb_fridge), ("ThermalHum", amb_thermal),
        ("SteamHiss", amb_steam), ("PhoneRing", amb_phone), ("MusicPad", amb_music_pad), ("MusicChasePad", amb_chase_pad),
    ],
    "horror": [
        ("ObserverStep", h_observer_step), ("ObserverInhale", h_observer_inhale), ("ObserverScreech", h_observer_screech),
        ("ObserverImpact", h_observer_impact), ("ObserverCrack", h_observer_crack), ("ObserverTwitch", h_observer_twitch),
        ("ObserverAppear", h_observer_appear), ("ObserverVanish", h_observer_vanish), ("ObserverSting", h_observer_sting),
        ("ObserverHunt", h_observer_hunt), ("ObserverRush", h_observer_rush), ("ObserverWhisperName", h_whisper_name),
        ("JumpSting", h_jump_sting), ("DeathHit", h_death_hit), ("TinnitusRing", h_tinnitus), ("Whisper", h_whisper),
        ("KnockDoor", h_knock_door), ("Thud", h_thud), ("DoorSlam", h_door_slam), ("DistantKnock", h_distant_knock),
        ("DistantPipe", h_distant_pipe), ("DistantMetal", h_distant_metal), ("DistantGroan", h_distant_groan),
        ("WoodCreak", h_wood_creak), ("ElevatorGroan", h_elevator_groan), ("BuildingSettle", h_building_settle),
        ("StretchGroan", h_stretch_groan), ("Falsetto", h_falsetto), ("MusicBox", h_music_box),
        ("RealityShift", h_reality_shift), ("RealitySnap", h_reality_snap), ("Heartbeat", h_heartbeat),
        ("HeartbeatFast", lambda: h_heartbeat(0.55, 0.16)), ("Breath", h_breath), ("BreathHeavy", h_breath_heavy),
        ("PowerDown", h_power_down), ("PowerOn", h_power_on), ("ElectricSurge", h_electric_surge), ("Sparks", h_sparks),
        ("BulbPop", h_bulb_pop), ("LightFlicker", h_light_flicker), ("Drip", h_drip), ("ExitUnlocked", h_exit_unlocked),
        ("TitleHit", h_title_hit), ("FootstepsBehind", h_footsteps_behind),
    ],
    "world": [
        ("StepConcrete", w_step("concrete")), ("StepTile", w_step("tile")), ("StepWood", w_step("wood")),
        ("StepMetal", w_step("metal")), ("StepCarpet", w_step("carpet")), ("DoorOpen", w_door_open),
        ("DoorClose", w_door_close), ("DoorLocked", w_door_locked), ("DoorUnlock", w_door_unlock),
        ("FuseInsert", w_fuse_insert), ("BreakerFlip", w_breaker_flip), ("KeypadBeep", w_keypad("beep")),
        ("KeypadError", w_keypad("error")), ("KeypadOk", w_keypad("ok")), ("DialTurn", w_dial_turn),
        ("TapeInsert", w_tape_insert), ("BoardsBreak", w_boards_break), ("ShutterOpen", w_shutter_open),
        ("PaperRustle", w_paper), ("Pickup", w_pickup), ("Drop", w_drop), ("Place", w_place),
        ("FlashlightOn", w_switch(2800)), ("FlashlightOff", w_switch(2200, 0.12, 0.7)), ("FlashlightDead", w_flashlight_dead),
        ("Equip", w_equip), ("ClockTick", w_clock_tick), ("LockRelease", w_lock_release), ("WardBreak", w_ward_break),
        ("EscapeDoor", w_escape_door), ("DeathFall", w_death_fall),
    ],
}


def write_ogg(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "6", path], check=True)
    os.remove(wav_path)


def main():
    os.makedirs(OUT, exist_ok=True)
    regions = {}
    for sheet, items in SHEETS.items():
        parts = [np.zeros(n_of(0.1))]
        cursor = 0.1
        for key, gen in items:
            x = gen()
            loop = sheet == "ambience"
            if not loop:
                x = norm(trim_tail(x), 0.85)
                # pure tones read far louder than noisy sounds: cap the loudness
                r = np.sqrt(np.mean(x ** 2))
                if r > 10 ** (-14 / 20):
                    x *= 10 ** (-14 / 20) / r
            start = cursor
            parts.append(x)
            cursor += len(x) / SR
            regions[key] = {"sheet": sheet, "start": round(start, 4), "stop": round(cursor, 4), "loop": loop}
            parts.append(np.zeros(n_of(GAP)))
            cursor += GAP
        audio = np.concatenate(parts)
        path = os.path.join(OUT, "dla_%s.ogg" % sheet)
        write_ogg(path, audio)
        print("%-9s %3d sounds  %6.1f s  %s" % (sheet, len(items), len(audio) / SR, os.path.relpath(path, ROOT)))
    with open(SHEETS_LUAU, "w", encoding="utf-8") as fh:
        fh.write("--[[\n\tAudioSheets (generated by tools/gen_audio.py - do not edit)\n")
        fh.write("\tWhere every custom sound lives inside the three uploaded audio files\n")
        fh.write("\t(assets/audio/dla_<sheet>.ogg). Times in seconds. Ids: Config/AssetIds.Audio.\n]]\n\n")
        fh.write("return {\n")
        for key in sorted(regions):
            r = regions[key]
            fh.write('\t%s = { sheet = "%s", start = %.4f, stop = %.4f },\n' % (key, r["sheet"], r["start"], r["stop"]))
        fh.write("}\n")
    with open(os.path.join(OUT, "regions.json"), "w") as fh:
        json.dump(regions, fh, indent=1)
    print("wrote", os.path.relpath(SHEETS_LUAU, ROOT), "(%d sounds)" % len(regions))


if __name__ == "__main__":
    main()
