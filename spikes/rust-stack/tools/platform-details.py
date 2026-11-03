#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005 -- Nix requires the interpreter directive on line two.
import json
import os
import subprocess
from pathlib import Path

assert os.uname().nodename == "aka"
assert os.environ.get("NIX_CONFIG") == "builders ="
source = Path(
    subprocess.check_output(
        [
            "nix",
            "eval",
            "--impure",
            "--raw",
            "--expr",
            "let f=builtins.getFlake (toString ./.); in f.inputs.nixpkgs.outPath",
        ],
        text=True,
    )
)
for name in ["sdl2", "sdl2-compat"]:
    matches = list(source.glob(f"pkgs/by-name/**/{name}/package.nix"))
    for path in matches:
        print(path, path.read_text())
pack = Path.home() / ".local/share/eggshell/packs/original-v3-final"
m = json.loads((pack / "manifest.json").read_text())
print("PLAYER_IDLE0", json.dumps(m["player"].get("Idle0")))
print("SECTIONS", list(m))
print("DENSITY", m.get("density"))
print(
    "TARGET_BACKGROUNDS",
    json.dumps({k: m["backgrounds"].get(k) for k in ["25", "46", "22"]}),
)
