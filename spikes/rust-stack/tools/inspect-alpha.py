#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.pillow
# ruff: noqa: EXE005
# Nix requires line2 interpreter metadata; it is not a misplaced OS shebang.
"""Private actual-GPU difference audit; no renderer or criterion changes."""

import json
from collections import Counter
from pathlib import Path

from PIL import Image

root = Path.home() / "eggshell-remote/artifacts/full-rust-ab"
a = Image.open(root / "reference-matrix-v1-companion-bubble.png").convert("RGBA")
b = Image.open(root / "owned-a8521cd-p1-companion-bubble.png").convert("RGBA")
assert a.size == b.size == (640, 480)
signed = [Counter() for _ in range(4)]
pairs = Counter()
parity = Counter()
examples = []
for y in range(480):
    for x in range(640):
        av = a.getpixel((x, y))
        bv = b.getpixel((x, y))
        if av == bv:
            continue
        delta = tuple(bv[i] - av[i] for i in range(4))
        for i in range(4):
            signed[i][delta[i]] += 1
        pairs[(av, bv)] += 1
        parity[(x % 4, y % 4)] += 1
        if len(examples) < 8:
            examples.append({"xy": [x, y], "A": av, "B": bv, "B_minus_A": delta})
report = {
    "mode": "actual-Pro-A-B-pixels-only-no-new-proof",
    "changed_pixels": sum(pairs.values()),
    "signed_channel_counts_B_minus_A": [dict(c) for c in signed],
    "most_common_pairs": [
        {"A": key[0], "B": key[1], "count": count}
        for key, count in pairs.most_common(20)
    ],
    "mod4_changed_counts": [
        {"xy_mod4": key, "count": value} for key, value in sorted(parity.items())
    ],
    "examples": examples,
}
out = root / "alpha-investigation-v1.json"
with out.open("x") as f:
    json.dump(report, f, indent=2)
print(json.dumps(report, indent=2))
