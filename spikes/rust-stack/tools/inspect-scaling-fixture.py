#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
# ruff: noqa: EXE005
"""AKA-only inspection of the unchanged synthetic benchmark base."""
import json
import socket
from pathlib import Path
assert socket.gethostname() == "aka"
p = Path("tests/fixtures/stride.level.json")
v = json.loads(p.read_text())
if isinstance(v,str):
    v=json.loads(v)
print(json.dumps(v,indent=2))
