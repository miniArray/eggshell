#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.pillow
# ruff: noqa: EXE005
"""Full-frame audit plus labelled diagnostic enlargement; not a cropped gate."""

import json
import socket
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

assert socket.gethostname() == "aka"
a_path, b_path, pack_path, out_path = map(Path, sys.argv[1:])
a = Image.open(a_path).convert("RGBA")
b = Image.open(b_path).convert("RGBA")
assert a.size == b.size == (640, 480)
points = []
for y in range(480):
    for x in range(640):
        av, bv = a.getpixel((x, y)), b.getpixel((x, y))
        if av != bv:
            points.append({"xy": [x, y], "A": av, "B": bv})
manifest = json.loads((pack_path / "manifest.json").read_text())
keys = [
    "countdown",
    "LifeCounter",
    "coins",
    "HUDIcons",
    "redcoins",
    "flowers",
    "MainFont",
    "ScoreFont",
    "LifeCounterFont",
]
metadata = {
    "density": manifest.get("density"),
    "hud": {k: manifest.get("hud", {}).get(k) for k in keys},
    "fonts": {k: manifest.get("fonts", {}).get(k) for k in keys},
    "coin": manifest.get("objects", {}).get("o1"),
}
report = {
    "purpose": "full-frame-audit-not-new-proof-no-criterion-change",
    "changed_pixels": len(points),
    "by_x": dict(sorted(Counter(p["xy"][0] for p in points).items())),
    "by_y": dict(sorted(Counter(p["xy"][1] for p in points).items())),
    "all_changed_points": points,
    "original_pack_metadata": metadata,
}
with out_path.with_suffix(".json").open("x") as f:
    json.dump(report, f, indent=2)
# All640columns of the32px top band, 4x nearest enlargement for human diagnosis.
# Never used as an equality gate; comparison above covers every full-frame pixel.
zoom = Image.new("RGBA", (2560, 256))
for row, image in enumerate([a, b]):
    zoom.paste(
        image.crop((0, 0, 640, 32)).resize((2560, 128), Image.Resampling.NEAREST),
        (0, row * 128),
    )
with out_path.with_suffix(".png").open("xb") as f:
    zoom.save(f, format="PNG")
print(json.dumps(report, indent=2))
