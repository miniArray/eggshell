#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005
"""Merge only successfully decoded real-screen asset bindings on AKA."""

import json
import os
import socket
from pathlib import Path

assert socket.gethostname() == "aka"
root = (
    Path.home()
    / "eggshell-remote/artifacts/full-rust-ab/scaling"
    / os.environ.get("REAL_SCREENS_DIR", "real-screens-v2")
)
reports = sorted(root.glob("asset-real-*.json"))
assert reports and len(reports) == len(list(root.glob("real-*.level.json")))
files = {}
omissions = {}
for path in reports:
    report = json.loads(path.read_bytes())
    assert report["mode"] == "asset-binding-only-no-gameplay-no-GPU"
    assert report["benchmark_real_screen"]
    assert not report["faithful_real_level"]
    omissions[path.name] = report["visual_omissions"]
    for row in report["files"]:
        if row["file"] in files:
            assert files[row["file"]] == row
        files[row["file"]] = row
merged = {
    "mode": "asset-binding-only-no-gameplay-no-GPU",
    "faithful_real_level": False,
    "files": list(files.values()),
    "image_count": len(files),
    "visual_omissions": omissions,
    "rgba_payload_bytes": sum(f["width"] * f["height"] * 4 for f in files.values()),
    "maximum_dimensions": [
        max(f[k] for f in files.values()) for k in ["width", "height"]
    ],
}
with (root / "real-assets.json").open("x") as handle:
    json.dump(merged, handle, separators=(",", ":"))
print(
    "REAL_SCREEN_ASSETS", json.dumps({k: v for k, v in merged.items() if k != "files"})
)
