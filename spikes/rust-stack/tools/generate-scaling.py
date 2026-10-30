#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005
"""Private AKA-only synthetic scaling inputs. No gameplay patches or public data."""

import copy
import hashlib
import itertools
import json
import socket
import sys
from pathlib import Path

assert socket.gethostname() == "aka"
source = Path("tests/fixtures/stride.level.json")
raw = source.read_bytes()
base = json.loads(raw)
assert isinstance(base, dict)
walker = base["maps"]["map1"]["objects"]["walker"]
assert walker["A"] == "e1" and walker["Y"] == 368
assert base["startpoint"] == {"map": 1, "X": 64, "Y": 384}
# Original retained flat floor: 32px tiles, 48 columns, rows12/13 solid.
layer = json.loads(base["maps"]["map1"]["layer1"]["castle32"])
assert layer == {"c2tilemap": True, "width": 48, "height": 14, "data": "576x-1,96x0"}
root = Path.home() / "eggshell-remote/artifacts/full-rust-ab/scaling"
root.mkdir(parents=True, exist_ok=True, mode=0o700)


def immutable(path, payload):
    if path.exists():
        assert path.read_bytes() == payload, f"refuse changed existing input: {path}"
    else:
        with path.open("xb") as f:
            f.write(payload)
    return hashlib.sha256(payload).hexdigest()


rows = []
for count in [25, 50, 100, 200, 400]:
    level = copy.deepcopy(base)
    objects = {}
    for i in range(count):
        enemy = copy.deepcopy(walker)
        enemy["X"] = round(160 + 624 * i / (count - 1), 3)
        assert 0 < enemy["X"] - 10 and enemy["X"] + 10 < 832
        assert enemy["Y"] + 16 == 384
        objects[f"walker-{i:04d}"] = enemy
    level["maps"]["map1"]["objects"] = objects
    # All other source facts including terrain/start/name remain identical.
    check = copy.deepcopy(level)
    check["maps"]["map1"]["objects"] = base["maps"]["map1"]["objects"]
    assert check == base
    path = root / f"scale-{count}.level.json"
    payload = (json.dumps(level, separators=(",", ":")) + "\n").encode()
    rows.append(
        {
            "N": count,
            "path": str(path),
            "sha256": immutable(path, payload),
            "x_range": [160, 784],
            "minimum_spacing_px": round(624 / (count - 1), 6),
            "enemy_hull_width_px": 20,
            "dense_hulls_overlap": count > 32,
            "ground_y": 384,
            "spawn_lifecycle_window": [0, 0, 832, 448],
            "benchmark_unverified_level": True,
        }
    )
idle = (json.dumps([0] * 1200, separators=(",", ":")) + "\n").encode()
idle_sha = immutable(root / "idle-1200.input.json", idle)
sums = (
    "".join(f"{r['sha256']}  {Path(r['path']).name}\n" for r in rows)
    + f"{idle_sha}  idle-1200.input.json\n"
)
immutable(root / "SHA256SUMS", sums.encode())
report = {
    "benchmark_unverified_level": True,
    "hint_only": True,
    "base_source_sha256": hashlib.sha256(raw).hexdigest(),
    "levels": rows,
    "idle_sha256": idle_sha,
    "density_limit": "400 unique supported ground positions fit. Hulls overlap at high N; walker-to-walker collision is not added or changed. All start inside fixed832x448 activation window, independent of renderer viewport.",
}
immutable(root / "generation.json", (json.dumps(report, indent=2) + "\n").encode())
print(json.dumps(report, indent=2))

# Separate immutable extension: do not rewrite the original scaling manifest.
if "--stress" in sys.argv:
    stress_rows = []
    for count in [1600, 2400]:
        level = copy.deepcopy(base)
        objects = {}
        for i in range(count):
            enemy = copy.deepcopy(walker)
            enemy["X"] = round(160 + 624 * i / (count - 1), 3)
            assert 0 < enemy["X"] - 10 and enemy["X"] + 10 < 832
            objects[f"walker-{i:04d}"] = enemy
        level["maps"]["map1"]["objects"] = objects
        name = f"scale-{count}.level.json"
        payload = (json.dumps(level, separators=(",", ":")) + "\n").encode()
        stress_rows.append(
            {"file": name, "N": count, "sha256": immutable(root / name, payload)}
        )
    target_path = (
        Path.home()
        / ".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"
    )
    target_raw = target_path.read_bytes()
    assert (
        hashlib.sha256(target_raw).hexdigest()
        == "bbe93d1592bcb6b9576c908ceae50518d42b031cf3f1997486a37daf4a062a17"
    )
    target = json.loads(target_raw)
    if isinstance(target, str):
        target = json.loads(target)
    original = target["maps"]["map1"]
    assert float(original["darkness"]) == 50
    dark = json.loads((root / "scale-400.level.json").read_bytes())
    copied = {
        key: copy.deepcopy(original[key])
        for key in ["bg1", "bg2", "bg3", "darkness", "bgcolor"]
        if key in original
    }
    assert all(
        str(copied[key]).split(",")[0] not in ["", "0"] for key in ["bg1", "bg2", "bg3"]
    )
    dark["maps"]["map1"].update(copied)
    assert (
        dark["maps"]["map1"]["objects"]
        == json.loads((root / "scale-400.level.json").read_bytes())["maps"]["map1"][
            "objects"
        ]
    )
    name = "scale-400-dark.level.json"
    payload = (json.dumps(dark, separators=(",", ":")) + "\n").encode()
    stress_rows.append(
        {
            "file": name,
            "N": 400,
            "sha256": immutable(root / name, payload),
            "copied_background_fields": copied,
            "terrain_and_start_retained": True,
            "target_objects_copied": False,
        }
    )
    for calls in [600, 36000]:
        name = f"idle-{calls}.input.json"
        payload = (json.dumps([0] * calls, separators=(",", ":")) + "\n").encode()
        stress_rows.append({"file": name, "sha256": immutable(root / name, payload)})
    immutable(
        root / "STRESS-SHA256SUMS",
        "".join(f"{r['sha256']}  {r['file']}\n" for r in stress_rows).encode(),
    )
    immutable(
        root / "stress-generation.json",
        (
            json.dumps(
                {
                    "benchmark_unverified_level": True,
                    "rows": stress_rows,
                    "target_source_sha256": hashlib.sha256(target_raw).hexdigest(),
                },
                indent=2,
            )
            + "\n"
        ).encode(),
    )
    print("STRESS_GENERATION", json.dumps(stress_rows))

if "--mixed" in sys.argv:
    mixed_root = root / "mixed-v2"
    mixed_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    columns, rows_count = 60, 30  # 1920x960, source-authored32px tiles
    cells = [-1] * (columns * rows_count)
    for row in [5, 9, 13, 17]:
        for column in range(6, columns):
            cells[row * columns + column] = 0
    for column in range(6):  # retained spawn floor, clear headroom at x64
        cells[12 * columns + column] = 0
    for column in range(columns):
        cells[29 * columns + column] = 0
    data = ",".join(
        f"{len(list(group))}x{value}" for value, group in itertools.groupby(cells)
    )
    tilemap = json.dumps(
        {"c2tilemap": True, "width": columns, "height": rows_count, "data": data},
        separators=(",", ":"),
    )
    dark_source = json.loads((root / "scale-400-dark.level.json").read_bytes())["maps"][
        "map1"
    ]
    dark_fields = {
        key: dark_source[key]
        for key in ["bg1", "bg2", "bg3", "darkness", "bgcolor"]
        if key in dark_source
    }
    mixed_rows = []
    for name, count, kinds, dark in [
        ("mix-500", 500, ["e1", "e2", "e3", "e5", "e35"], False),
        ("mix-2000", 2000, ["e1", "e2", "e3", "e5", "e35"], False),
        ("mix-500-dark", 500, ["e1", "e2", "e3", "e5", "e35"], True),
        ("wide-400-dark", 400, ["e1"], True),
    ]:
        level = copy.deepcopy(base)
        m = level["maps"]["map1"]
        m.update(
            {
                "width": 1920,
                "height": 960,
                "objects": {},
                "layer1": {"castle32": tilemap},
            }
        )
        if dark:
            m.update(dark_fields)
        per_row = count // 4
        for i in range(count):
            tier, column = divmod(i, per_row)
            code = kinds[i % len(kinds)]
            enemy = {
                "A": code,
                "F": 0,
                "X": round(224 + 384 * column / (per_row - 1), 3),
                "Y": [160, 288, 416, 544][tier] - 16,
            }
            if code == "e35":
                enemy["E1"] = 50
            m["objects"][f"mixed-{i:04d}"] = enemy
        payload = (json.dumps(level, separators=(",", ":")) + "\n").encode()
        filename = f"{name}.level.json"
        mixed_rows.append(
            {
                "file": filename,
                "N": count,
                "codes_interleaved": kinds,
                "counts_per_type": {code: count // len(kinds) for code in kinds},
                "sha256": immutable(mixed_root / filename, payload),
                "size_px": [1920, 960],
                "floor_rows_px": [160, 288, 416, 544],
                "enemy_x_range": [224, 608],
                "initial_scale1_view_px": [0, 116, 640, 596],
                "all_enemy_placements_in_initial_lifecycle_window": True,
                "dense_hulls_overlap": True,
                "target_darkness_and_backgrounds": dark,
            }
        )
    immutable(
        mixed_root / "MIXED-SHA256SUMS",
        "".join(f"{row['sha256']}  {row['file']}\n" for row in mixed_rows).encode(),
    )
    immutable(
        mixed_root / "mixed-generation.json",
        (
            json.dumps(
                {"benchmark_unverified_level": True, "rows": mixed_rows}, indent=2
            )
            + "\n"
        ).encode(),
    )
    print("MIXED_GENERATION", json.dumps(mixed_rows))
