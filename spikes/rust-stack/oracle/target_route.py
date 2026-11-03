#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i python3
# ruff: noqa: EXE005 -- nix-shell requires a second shebang directive.
"""First normal-input target exploration. Coverage is measured, never assumed.

No target state edits or teleports. This is not an admitted benchmark route.
"""

import json
import os
import socket
import sys
from pathlib import Path

if socket.gethostname() != "aka":
    raise SystemExit("Data processing must run on aka")
if "builders =" not in os.environ.get("NIX_CONFIG", ""):
    raise SystemExit("Remote builders must be disabled")
# Walk/jump/tongue through normally reached states. Deliberately alternate short
# jump holds and released intervals, including ordinary restarts after pits.
inputs = []
for tick in range(7200):
    phase = tick % 120
    mask = 2
    if phase < 32:
        mask |= 4
    if phase in (42, 62, 82):
        mask |= 8
    if phase == 100:
        mask |= 64
    if phase == 104:
        mask |= 64
    inputs.append(mask)
Path(sys.argv[1]).write_text(json.dumps(inputs, separators=(",", ":")) + "\n")
print(f"TARGET_INPUT_DONE ticks={len(inputs)} path={sys.argv[1]}", flush=True)
