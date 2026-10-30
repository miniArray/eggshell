#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i python3
# ruff: noqa: EXE005 -- nix-shell requires a second shebang directive.
"""Named normal-input fixture routes. No state edits and no target benchmark route."""

import json
import os
import socket
import sys
from pathlib import Path


def main() -> None:
    if socket.gethostname() != "aka" or "builders =" not in os.environ.get(
        "NIX_CONFIG", ""
    ):
        raise RuntimeError("Route processing requires aka with builders disabled")
    name, destination = sys.argv[1:]
    if name == "bounce.pad":
        # Existing Bounce flies over the pad. Tap/release jump to fall onto it.
        inputs = [2] * 60 + [6] + [2] * 739
    elif name == "collections":
        inputs = [2] * 800
    elif name == "actors_target":
        inputs = [2] * 1600
    elif name == "stilts_target.knock":
        inputs = [2] * 20 + [10] + [2] * 779
    elif name == "stilts_target":
        inputs = [2] * 8 + [6] * 45 + [2] * 41 + [6] * 55 + [2] * 651
    else:
        raise ValueError(f"unknown verification route: {name}")
    Path(destination).write_text(json.dumps(inputs, separators=(",", ":")) + "\n")
    print(f"NORMAL_ROUTE_DONE route={name} inputs={len(inputs)} state_edits=0")


if __name__ == "__main__":
    main()
