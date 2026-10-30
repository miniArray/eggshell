#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005 -- Nix requires the interpreter directive on line two.
import json
import os
from pathlib import Path

assert os.uname().nodename == "aka"
assert os.environ.get("NIX_CONFIG") == "builders ="
p = Path.home() / ".local/share/eggshell/packs/original-v3-final"
m = json.loads((p / "manifest.json").read_text())
for name in ["hud", "MainFont", "ScoreFont", "LifeCounterFont"]:
    font = m["fonts"].get(name)
    if font:
        print("FONT", name, json.dumps(font))
for section, code in [
    ("objects", key)
    for key in [
        "e5_head",
        "e35",
        "o23",
        "p1",
        "d1",
        "d2",
        "d4",
        "companion",
        "bubble",
        "rescue",
    ]
] + [
    ("hud", key)
    for key in ["companion", "bubble", "rescuer", "LifeCounter", "HUDIcons"]
]:
    entry = m[section].get(code)
    if entry:
        print(
            section,
            code,
            json.dumps(
                {
                    k: v
                    for k, v in entry.items()
                    if k
                    in [
                        "anchor",
                        "facing",
                        "origin",
                        "slices",
                        "file",
                        "default_animation",
                        "states",
                    ]
                }
            ),
            "animation_count",
            len(entry.get("animations", {})),
        )
    else:
        print(section, code, "MISSING")
print("TERRAIN_SECTIONS", list(m.get("terrain", {})))
level_path = (
    Path.home()
    / ".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"
)
outer = json.loads(level_path.read_text())
level = json.loads(outer) if isinstance(outer, str) else outer
for name, source in level["maps"].items():
    print(
        "TARGET_EFFECTS",
        name,
        {
            k: source.get(k)
            for k in [
                "gradient",
                "customGradientGenerator",
                "caveShimmer",
                "tint",
                "darkness",
            ]
        },
    )
