#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005
"""AKA-only private census/source inspection, no image or Godot work."""

import json
import socket
from collections import Counter
from pathlib import Path

assert socket.gethostname() == "aka"
ids = [
    "66476d1f0e6c18cafbaaf355",
    "6aa65f0c574012395a0faddf",
    "64d3d5f1d77b3fe14198c693",
]
root = Path.home() / "eggshell-remote/artifacts/full-rust-ab"
census = json.loads((root / "speed/onscreen-census-v2.json").read_text())
print(
    "CENSUS_ROOT", list(census) if isinstance(census, dict) else type(census).__name__
)


def find(value, path="root"):
    if isinstance(value, dict):
        if any(
            isinstance(v, str) and any(code in v for code in ids)
            for v in value.values()
        ):
            print("CENSUS_ENTRY", path, json.dumps(value))
        for k, v in value.items():
            if k in ids:
                print("CENSUS_ID_ENTRY", k, json.dumps(v))
            else:
                find(v, path + "." + str(k))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            find(v, path + "." + str(i))


find(census)
for code in ids:
    path = Path.home() / f".local/share/eggshell-run/corpus/levels/{code}.json"
    level = json.loads(path.read_bytes())
    if isinstance(level, str):
        level = json.loads(level)
    print("REAL_LEVEL", code, "start", level.get("startpoint"), "fields", list(level))
    for name, m in level["maps"].items():
        print(
            "REAL_MAP",
            code,
            name,
            "size",
            m.get("width"),
            m.get("height"),
            "fields",
            list(m),
            "codes",
            dict(Counter(v["A"] for v in m["objects"].values())),
            "drawing",
            {
                k: m[k]
                for k in [
                    "bg1",
                    "bg2",
                    "bg3",
                    "bgcolor",
                    "darkness",
                    "tint",
                    "gradient",
                    "caveShimmer",
                    "diceBlockColours",
                ]
                if k in m
            },
            "layernames",
            {k: list(m.get(k, {})) for k in ["layer1", "layer2"]},
        )
