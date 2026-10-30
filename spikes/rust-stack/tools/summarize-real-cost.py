#!/usr/bin/env python3
"""AKA-only inclusive simulation-stack counts and scene-work summary."""

import collections
import json
import re
import socket
import sys
from pathlib import Path

assert socket.gethostname() == "aka"
root = Path(sys.argv[1])
profiles = {}
for file in sorted(root.glob("*.perf.script.txt")):
    counts = collections.Counter()
    leaf = collections.Counter()
    selected = 0
    all_samples = 0
    for stack in file.read_text().split("\n\n"):
        if not stack.strip():
            continue
        all_samples += 1
        if "profile_step" not in stack:
            continue
        names = []
        for line in stack.splitlines():
            match = re.match(r"\s+[0-9a-f]+\s+(.*)", line)
            if match:
                name = match[1].rsplit(" (", 1)[0].split("+0x", 1)[0]
                names.append(name)
        if not names:
            continue
        selected += 1
        counts.update(set(names))
        leaf.update(names[:1])
    assert selected > 0, f"no simulation-marker stacks in {file}"
    profiles[file.name] = {
        "simulation_samples": selected,
        "all_samples": all_samples,
        "top15_inclusive": [
            {
                "function": name,
                "samples": count,
                "percent": round(count * 100 / selected, 2),
            }
            for name, count in counts.most_common(15)
        ],
        "top15_self": [
            {
                "function": name,
                "samples": count,
                "percent": round(count * 100 / selected, 2),
            }
            for name, count in leaf.most_common(15)
        ],
    }
work = {}
for file in sorted(root.glob("*.work.json")):
    report = json.loads(file.read_bytes())
    work[file.name] = {
        "first_tick_row_classification": report["first_tick_row_classification"],
        "records": [],
    }
    for row in report["records"]:
        short = {k: v for k, v in row.items() if k != "work"}
        short["work"] = {
            k: v
            for k, v in row["work"].items()
            if k not in ["tile_layers", "entity_layers"]
        }
        short["stored_cells"] = sum(
            r["stored_cells"] for r in row["work"]["tile_layers"]
        )
        short["tile_layer_count"] = len(row["work"]["tile_layers"])
        work[file.name]["records"].append(short)
summary = {
    "source_sha": (root / "source-sha.txt").read_text().strip(),
    "scope": "release AKA host only, not Pro timing; inclusive unique functions per stack, filtered to profile_step; scene counters from separate feature build",
    "profiles": profiles,
    "scene_work": work,
}
with (root / "summary.json").open("x") as handle:
    json.dump(summary, handle, indent=2)
print("REAL_COST_DIAGNOSIS", json.dumps(summary))
