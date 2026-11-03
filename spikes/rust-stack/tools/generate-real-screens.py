#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005
"""AKA-only, private real-position rebuild; never writes corpus or Git."""

import copy
import hashlib
import json
import math
import os
import socket
import sys
from collections import Counter
from pathlib import Path

assert socket.gethostname() == "aka"
root = Path.home() / "eggshell-remote/artifacts/full-rust-ab"
out = root / "scaling" / os.environ.get("REAL_SCREENS_DIR", "real-screens-v2")
out.mkdir(mode=0o700, exist_ok=True)
if (root / "speed/onscreen-census-all.json").exists():
    census = json.loads((root / "speed/onscreen-census-all.json").read_text())
    entries = census["all"]
else:
    census = json.loads((root / "speed/onscreen-census-v2.json").read_text())
    entries = census["top10"] + [census["heavy_64d3d5f1"]]
requested = sys.argv[1:]
assert requested and len(set(requested)) == len(requested)
kinds = ["e1", "e2", "e3", "e5", "e35"]
supported = set(
    kinds + ["o1", "o2", "o3", "o4", "o5", "o6", "o11", "o23", "p1", "d1", "d2", "d4"]
)


def number(obj, key, default=0):
    try:
        value = float(obj.get(key, default))
        return value if math.isfinite(value) else None
    except (ValueError, TypeError):
        return None


def can_load(obj):
    code = obj["A"]
    if code not in supported:
        return False
    variant, rotation, mirror = (number(obj, k) for k in ["F", "R", "M"])
    if code in kinds:
        return (
            rotation == 0
            and mirror in [0, 1, 2]
            and variant in range(5 if code in ["e1", "e2", "e35"] else 2)
            and (code != "e35" or number(obj, "E1", 50) is not None)
        )
    if code in ["d1", "d2", "d4"]:
        return variant == 0 and mirror == 0 and rotation == 0
    if code == "o6":
        return all(number(obj, k, None) is not None for k in ["E1", "E2"])
    return True


def write(name, value):
    data = (
        json.dumps(value, separators=(",", ":"), ensure_ascii=False) + "\n"
    ).encode()
    with (out / name).open("xb") as handle:
        handle.write(data)
    return hashlib.sha256(data).hexdigest()


reports = []
for ident in requested:
    entry = next(e for e in entries if e["level"] == ident)
    source = Path.home() / f".local/share/eggshell-run/corpus/levels/{ident}.json"
    raw = source.read_bytes()
    original = json.loads(raw)
    if isinstance(original, str):
        original = json.loads(original)
    level = copy.deepcopy(original)
    replacements = []
    cursor = 0
    for name, room in level["maps"].items():
        for object_id, obj in sorted(
            room["objects"].items(),
            key=lambda pair: (float(pair[1]["Y"]), float(pair[1]["X"]), pair[0]),
        ):
            if can_load(obj):
                continue
            code = kinds[cursor % len(kinds)]
            cursor += 1
            replacements.append(
                {
                    "map": name,
                    "id": object_id,
                    "from": obj["A"],
                    "to": code,
                    "reason": "unsupported-code-or-form",
                }
            )
            obj.update(A=code, F=0, M=0, R=0)
            if code == "e35":
                obj["E1"] = 50
        source_room = original["maps"][name]
        assert set(room["objects"]) == set(source_room["objects"])
        for key, value in source_room.items():
            if key != "objects":
                assert room[key] == value, (name, key)
        assert all(
            (obj["X"], obj["Y"])
            == (source_room["objects"][key]["X"], source_room["objects"][key]["Y"])
            for key, obj in room["objects"].items()
        )
    origin = entry["window_origin_px"]
    visible = entry["view_world_px"]
    center = [origin[i] + visible[i] / 2 for i in range(2)]
    level["startpoint"].update(
        map=int(entry["map"].removeprefix("map")), X=center[0], Y=center[1] + 28
    )
    filename = f"real-{ident}.level.json"
    sha = write(filename, level)
    report = {
        "file": filename,
        "source_id": ident,
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "sha256": sha,
        "faithful_real_level": False,
        "all_map_nonobject_fields_preserved": True,
        "all_object_ids_positions_preserved": True,
        "source_census": entry,
        "requested_camera_center": center,
        "startpoint": level["startpoint"],
        "replacements": replacements,
        "replaced_count": len(replacements),
        "replacement_counts": dict(Counter(r["to"] for r in replacements)),
        "substitution_order": "spatial Y,X,id; e1,e2,e3,e5,e35 cycle",
        "source_object_count": sum(
            len(m["objects"]) for m in original["maps"].values()
        ),
    }
    reports.append(report)
    print(
        "REAL_SCREEN_GENERATED",
        json.dumps({k: v for k, v in report.items() if k != "replacements"}),
    )
write(
    "real-screens-generation.json",
    {
        "faithful_real_level": False,
        "levels": reports,
        "visual_policy": "explicit benchmark-only opaque fullscreen gradient stand-ins, original fields retained; diceBlockColours omitted; no tile/background omissions allowed",
    },
)
print("REAL_SCREENS_GENERATED", out)
