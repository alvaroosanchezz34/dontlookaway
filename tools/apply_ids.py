"""
Writes uploaded ids into src/shared/Config/AssetIds.luau, then re-syncs.

    python3 tools/apply_ids.py "DLA_MESH Head=123,Sofa=456,..."
    python3 tools/apply_ids.py --json build/uploaded_ids.json

DLA_MESH (tools/studio/export_mesh_ids.luau): mesh ids of the imported .obj
models -> AssetIds.Observer.meshes[Segment] / AssetIds.PropMeshes[Prop].mesh
(a mesh id wins over a model id in both loaders).

--json (tools/upload_assets.py): {"<file path>": id} for the uploaded maps and
audio -> ObserverSkins, PropMeshes, Materials, Decals, Audio.
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
IDS = os.path.join(ROOT, "src", "shared", "Config", "AssetIds.luau")
OBSERVER = {"Head", "Neck", "UpperTorso", "LowerTorso", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"}


def block_span(src, header):
    """(start, end) of `AssetIds.X = { ... }` (top-level, closing brace at column 0)."""
    m = re.search(re.escape(header) + r"\s*=\s*\{", src)
    if not m:
        return None
    end = src.index("\n}", m.end())
    return m.start(), end + 2


def set_field(src, header, entry, field, value):
    """Sets `field = value` inside `entry = { ... }` of block `header` (adds it if absent)."""
    span = block_span(src, header)
    if not span:
        raise SystemExit("no block " + header)
    a, b = span
    block = src[a:b]
    m = re.search(r"(\n\t+%s = \{)([^}]*)(\})" % re.escape(entry), block)
    if not m:
        raise SystemExit("no entry %s in %s" % (entry, header))
    body = m.group(2)
    if re.search(r"\b%s = \d+" % field, body):
        body = re.sub(r"\b%s = \d+" % field, "%s = %d" % (field, value), body)
    else:
        body = " %s = %d," % (field, value) + body
    block = block[: m.start(2)] + body + block[m.end(2) :]
    return src[:a] + block + src[b:]


def set_plain(src, header, key, value):
    """Sets `key = value` directly inside block `header`, or inside its sub-table."""
    span = block_span(src, header)
    a, b = span
    block = src[a:b]
    block, n = re.subn(r"(\n\t+%s = )\d+" % re.escape(key), r"\g<1>%d" % value, block, count=1)
    if n == 0:
        raise SystemExit("no key %s in %s" % (key, header))
    return src[:a] + block + src[b:]


def apply_mesh_line(src, line):
    pairs = re.findall(r"(\w+)=(\d+)", line.replace("DLA_MESH", " "))
    done = []
    for name, value in pairs:
        value = int(value)
        if name in OBSERVER:
            # inside AssetIds.Observer.meshes
            a, b = block_span(src, "AssetIds.Observer")
            block = src[a:b]
            ms = block.index("\tmeshes = {")
            me = block.index("\n\t}", ms)
            sub = re.sub(r"(\t\t%s = )\d+" % name, r"\g<1>%d" % value, block[ms:me], count=1)
            src = src[:a] + block[:ms] + sub + block[me:] + src[b:]
        else:
            src = set_field(src, "AssetIds.PropMeshes", name, "mesh", value)
        done.append(name)
    return src, done


def apply_json(src, mapping):
    done = []
    for path, value in mapping.items():
        p = path.replace("\\", "/")
        value = int(value)
        m = re.search(r"assets/fbx/(\w+)\.fbx$", p)
        if m:
            name = m.group(1)
            if name in OBSERVER:
                a, b = block_span(src, "AssetIds.Observer")
                block = src[a:b]
                for sub_name, val in (("models", value), ("meshes", 0)):
                    ms = block.index("\t%s = {" % sub_name)
                    me = block.index("\n\t}", ms)
                    block = block[:ms] + re.sub(r"(\t\t%s = )\d+" % name, r"\g<1>%d" % val, block[ms:me], count=1) + block[me:]
                src = src[:a] + block + src[b:]
            else:
                src = set_field(src, "AssetIds.PropMeshes", name, "model", value)
                src = set_field(src, "AssetIds.PropMeshes", name, "mesh", 0)
            done.append(p)
            continue
        m = re.search(r"assets/observer/(\w+)/\1_(color|normal|roughness)\.png$", p)
        if m:
            src = set_field(src, "AssetIds.ObserverSkins", m.group(1), m.group(2), value)
            done.append(p)
            continue
        m = re.search(r"assets/props/(\w+)/\1_(color|normal|roughness|metalness)\.png$", p)
        if m:
            src = set_field(src, "AssetIds.PropMeshes", m.group(1), m.group(2), value)
            done.append(p)
            continue
        m = re.search(r"assets/textures/(\w+)/\1_(color|normal|roughness|metalness)\.png$", p)
        if m:
            src = set_field(src, "AssetIds.Materials", m.group(1), m.group(2), value)
            done.append(p)
            continue
        m = re.search(r"assets/decals/(\w+)\.png$", p)
        if m:
            src = set_plain(src, "AssetIds.Decals", m.group(1), value)
            done.append(p)
            continue
        m = re.search(r"assets/audio/dla_(\w+)\.(ogg|mp3)$", p)
        if m:
            src = set_plain(src, "AssetIds.Audio", m.group(1), value)
            done.append(p)
            continue
        print("skipped (unknown file):", p)
    return src, done


def main():
    args = sys.argv[1:]
    src = open(IDS, encoding="utf-8").read()
    if args[:1] == ["--json"]:
        src, done = apply_json(src, json.load(open(args[1], encoding="utf-8")))
    else:
        src, done = apply_mesh_line(src, " ".join(args))
    open(IDS, "w", encoding="utf-8").write(src)
    print("wrote %d ids" % len(done))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sync_assets.py")], check=True)


if __name__ == "__main__":
    main()
