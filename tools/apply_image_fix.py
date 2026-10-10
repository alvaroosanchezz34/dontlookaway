"""
Applies the Decal -> Image id fixes printed by tools/studio/check_image_ids.luau:

    python3 tools/apply_image_fix.py "DLA_FIX 123:122,456:455"

Rewrites every listed id in the id config files, then runs sync_assets.py so the
MaterialVariants, the Observer skin and the prop skins pick up the new ids.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
FILES = [
    os.path.join(ROOT, "src", "shared", "Config", "AssetIds.luau"),
    os.path.join(ROOT, "src", "marketing", "shared", "MarketingConfig.luau"),
]


def main():
    text = " ".join(sys.argv[1:]).replace("DLA_FIX", " ")
    pairs = re.findall(r"(\d+):(\d+)", text)
    if not pairs:
        sys.exit("no id pairs found (expected 'DLA_FIX old:new,old:new')")
    fixes = {old: new for old, new in pairs}
    done = set()
    for path in FILES:
        with open(path, encoding="utf-8") as fh:
            src = fh.read()

        def swap(m):
            if m.group(0) in fixes:
                done.add(m.group(0))
                return fixes[m.group(0)]
            return m.group(0)

        out = re.sub(r"(?<![\d.])\d{6,}(?![\d.])", swap, src)
        if out != src:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(out)
    missing = set(fixes) - done
    print("fixed %d of %d ids%s" % (len(done), len(fixes), "; not found: " + ", ".join(sorted(missing)) if missing else ""))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sync_assets.py")], check=True)


if __name__ == "__main__":
    main()
