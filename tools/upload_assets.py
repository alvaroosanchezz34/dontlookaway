"""
Uploads the game's images and audio to a Roblox GROUP with Open Cloud and
writes their ids into AssetIds.luau - no Asset Manager, no screenshots.
Run it on your own computer (it needs your API key and internet access to
apis.roblox.com). Python 3.8+, no extra packages.

    1. create.roblox.com -> (select the group) -> Open Cloud -> API Keys ->
       Create API Key: add "Assets API" with Read + Write, the IP of your PC
       (or 0.0.0.0/0), save the key somewhere private.
    2. The group id is the number in the group's page address.
    3. In the repo:
         set ROBLOX_API_KEY=...        (PowerShell: $env:ROBLOX_API_KEY="...")
         python tools/upload_assets.py --group 12345678 observer props audio
       Sets: observer (30 maps), props (~57 maps), audio (3 sounds),
             textures (54 maps), decals, film (2 grain sheets). Default: observer props audio.
       --dry-run lists what would be uploaded.
    4. It writes build/uploaded_ids.json and the ids into AssetIds.luau
       (tools/apply_ids.py), then runs sync_assets.py. Commit and push.
    5. Images come back as Decal ids: in Studio run
       tools/studio/check_image_ids.luau once and apply its DLA_FIX line
       (python tools/apply_image_fix.py "DLA_FIX ...").

Meshes (.obj) are not uploaded here (Open Cloud does not take .obj): import
them in Studio and use tools/studio/export_mesh_ids.luau.
Never commit the API key. Already uploaded files (in build/uploaded_ids.json)
are skipped, so the script can be re-run after a failure.
"""

import argparse
import glob
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "build", "uploaded_ids.json")
API = "https://apis.roblox.com/assets/v1"

SETS = {
    "observer": ("Decal", "assets/observer/*/*.png"),
    "props": ("Decal", "assets/props/*/*.png"),
    "textures": ("Decal", "assets/textures/*/*.png"),
    "decals": ("Decal", "assets/decals/*.png"),
    "film": ("Decal", "assets/film/*.png"),
    "audio": ("Audio", "assets/audio/dla_*.ogg"),
}


def multipart(fields, file_field, path):
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, name, value)).encode()
    ctype = mimetypes.guess_type(path)[0] or ("audio/ogg" if path.endswith(".ogg") else "application/octet-stream")
    body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % (boundary, file_field, os.path.basename(path), ctype)).encode()
    body += open(path, "rb").read()
    body += ("\r\n--%s--\r\n" % boundary).encode()
    return bytes(body), "multipart/form-data; boundary=" + boundary


def call(method, url, key, data=None, ctype=None):
    for attempt in range(6):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("x-api-key", key)
        if ctype:
            req.add_header("Content-Type", ctype)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503) and attempt < 5:
                time.sleep(2 ** attempt * 2)
                continue
            raise SystemExit("%s %s -> HTTP %d: %s" % (method, url, e.code, text[:400]))
    raise SystemExit("gave up on " + url)


def upload(path, kind, group, key):
    name = os.path.splitext(os.path.basename(path))[0]
    request = {
        "assetType": kind,
        "displayName": ("DLA " + name)[:50],
        "description": "DON'T LOOK AWAY - " + os.path.relpath(path, ROOT).replace("\\", "/"),
        "creationContext": {"creator": {"groupId": str(group)}},
    }
    data, ctype = multipart({"request": json.dumps(request)}, "fileContent", path)
    op = call("POST", API + "/assets", key, data, ctype)
    # the upload is an operation: wait until it is done
    for _ in range(60):
        if op.get("done"):
            resp = op.get("response") or {}
            asset = resp.get("assetId") or (resp.get("asset") or {}).get("assetId")
            if not asset:
                raise SystemExit("no asset id for %s: %s" % (path, json.dumps(op)[:400]))
            return int(asset)
        time.sleep(1.5)
        op = call("GET", API + "/" + op["path"], key)
    raise SystemExit("timed out waiting for " + path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--group", required=True, type=int)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("sets", nargs="*", default=["observer", "props", "audio"])
    args = ap.parse_args()
    key = os.environ.get("ROBLOX_API_KEY", "")
    if not key and not args.dry_run:
        raise SystemExit("set ROBLOX_API_KEY first (see the top of this file)")
    done = json.load(open(OUT)) if os.path.exists(OUT) else {}
    files = []
    for s in args.sets:
        kind, pattern = SETS[s]
        files += [(p, kind) for p in sorted(glob.glob(os.path.join(ROOT, pattern)))]
    todo = [(p, k) for p, k in files if os.path.relpath(p, ROOT).replace("\\", "/") not in done]
    print("%d files, %d already uploaded, %d to upload" % (len(files), len(files) - len(todo), len(todo)))
    if args.dry_run:
        for p, k in todo:
            print("  %-6s %s" % (k, os.path.relpath(p, ROOT)))
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    for i, (path, kind) in enumerate(todo, 1):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        asset = upload(path, kind, args.group, key)
        done[rel] = asset
        json.dump(done, open(OUT, "w"), indent=1)
        print("[%d/%d] %s -> %d" % (i, len(todo), rel, asset))
        time.sleep(1.2)  # stay well under the rate limit
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "apply_ids.py"), "--json", OUT], check=True)
    print("done: ids written to AssetIds.luau. Now run tools/studio/check_image_ids.luau in Studio.")


if __name__ == "__main__":
    main()
