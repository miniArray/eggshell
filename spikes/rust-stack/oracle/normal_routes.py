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
    if name == "stride.eat":
        # P1 eating: the damage route reaches food at call 152; catch it and lay an
        # egg with DOWN (consume, then the stored egg), then walk on and try a
        # second catch and a spit.
        damage = json.loads(Path("tests/fixtures/stride.damage.input.json").read_text())
        # The catch lands as the hit lands; actions resume when the hurt lock ends (~call 222).
        inputs = (
            damage[:152]
            + [10]
            + [0] * 76
            + [32]
            + [0] * 40
            # Aim (THROW), then throw the laid egg (THROW again).
            + [64]
            + [0] * 15
            + [64]
            + [0] * 60
            + [2] * 30
            + [8]
            + [0] * 20
            + [8]
            + [0] * 40
        )
        inputs += [2] * (800 - len(inputs))
    elif name == "bounce.moves":
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
    elif name == "spans_target":
        # Hop right through the spans from below and land on them; pauses let the body
        # walk off span ends and stand still on a top edge; a DOWN tap ducks on a span.
        cycle = [6] * 14 + [2] * 16 + [0] * 8 + [32] * 4 + [2] * 10
        inputs = cycle * 30 + [2] * 200
    elif name == "blocks_target":
        # Walk right jumping into each block from below; tap DOWN (page/close a message,
        # duck) and THROW (aim, then throw a collected egg into the blocks) every cycle.
        cycle = [6] * 10 + [2] * 12 + [34] + [2] * 5 + [66] + [2] * 3
        inputs = cycle * 40 + [2] * 300
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
