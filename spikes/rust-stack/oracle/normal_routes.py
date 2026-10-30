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
    if name == "bounce.moves":
        # P1 player actions without food: look up, upward tongue, toss and aim
        # without eggs, aim lock, duck + throw, airborne throw and tongues.
        inputs = (
            [0] * 30
            + [2] * 40
            + [0] * 20
            + [16] * 30
            + [0] * 10
            + [24]
            + [16] * 20
            + [0] * 20
            + [64]
            + [0] * 20
            + [128]
            + [0] * 10
            + [66]
            + [2] * 20
            + [6]
            + [4] * 10
            + [68]
            + [4] * 10
            + [0] * 30
            + [32] * 20
            + [96]
            + [32] * 5
            + [0] * 20
            + [4] * 9
            + [28]
            + [4] * 10
            + [0] * 30
            + [1] * 60
            + [9]
            + [0] * 20
            + [8]
            + [0] * 5
            + [8]
            + [0] * 20
        )
        inputs += [2] * (800 - len(inputs))
    elif name == "bounce.pad":
        # Existing Bounce flies over the pad. Tap/release jump to fall onto it.
        inputs = [2] * 60 + [6] + [2] * 739
    elif name == "collections":
        inputs = [2] * 800
    elif name == "actors_target":
        inputs = [2] * 1600
    elif name == "posts_target.duck":
        inputs = [6] * 45 + [0] * 35 + [32] * 20 + [0] * 20 + [2] * 680
    elif name == "posts_target.pound":
        inputs = [6] * 45 + [0] * 35 + ([4] * 12 + [32] * 50 + [0] * 10) * 3 + [2] * 504
    elif name == "posts_target":
        inputs = [6] * 45 + [0] * 135 + [2] * 620
    elif name == "checkpoint_target":
        inputs = [2] * 2400
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
