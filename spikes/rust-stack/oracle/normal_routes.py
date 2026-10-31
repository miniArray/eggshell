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
    elif name == "melons_target":
        # Wait for the high melon to land, lick it (30 seeds) and hold USE to spit them
        # right at the walkers, stilt and coin; walk on, hop the rock, lick the F 1 melon
        # (10 seeds) and spit at the shell, then the F 2 melon (60 seeds) at the last
        # walker.
        eat = [8] + [0] * 45
        inputs = [0] * 30 + [2] * 16 + eat + [8] * 170 + [0] * 30
        inputs += [2] * 150 + [6] * 14 + [2] * 26 + [0] * 30 + eat + [8] * 60 + [0] * 20
        inputs += [2] * 70 + [0] * 30 + eat + [8] * 310 + [0] * 30 + [2] * 200
    elif name == "fish_target":
        # Stand back while the fish patrol, leap and arc; then hop past the flopper and
        # wade into the pool, swimming (jump presses) and licking.
        swim = [6] * 8 + [2] * 20 + [8] + [0] * 20
        # The three-jump fish needs about 2300 ticks to use its jumps and finish.
        inputs = [0] * 600 + [2] * 60 + swim * 20 + [2] * 300 + [0] * 700
    elif name == "snowflow_target":
        # Walk into the right-pushing flow and stand in it, jump into the waterfall,
        # cross both slopes (jumping on one), run onto the snow, reverse on it (the
        # light brake), slide to a stop, and hop along the snow.
        inputs = [2] * 40 + [0] * 60 + [2] * 30 + [6] * 14 + [2] * 10 + [0] * 40
        inputs += [2] * 40 + [0] * 30 + [4] * 10 + [0] * 30 + [2] * 80 + [1] * 40
        inputs += [2] * 40 + [0] * 60 + [6] * 14 + [0] * 40 + [1] * 30 + [5] * 14
        inputs += [0] * 60 + [2] * 300
    elif name == "lifts_target":
        # Hop onto the first wheel and ride it into the rock (it reflects), jump off,
        # hop onto the timed wheel and ride until it shrinks away, then hop on through.
        # The decks are top-only: stand under a wheel and jump straight up onto it.
        up = [4] * 14 + [0] * 40
        inputs = [2] * 44 + [0] * 20 + up + [0] * 300 + [6] * 14 + [2] * 6 + [0] * 40
        inputs += [2] * 120 + [0] * 20 + up + [0] * 260
        inputs += ([6] * 14 + [2] * 20 + [0] * 20) * 12 + [2] * 300
    elif name == "rollers_target":
        # Eat the walker, lay an egg and throw it at the first hanging roller (it laughs,
        # drops, rolls into Yoshi and stops at the border); walk right, hop over the low
        # roller, and stand under the second: it drops and rolls left through the low
        # one (entry-contact memory, a laugh) and the respawned first one.
        inputs = [0] * 20 + [2] * 12 + [8] + [0] * 30 + [32] + [0] * 40
        inputs += [64] + [0] * 14 + [64] + [0] * 260 + [2] * 103 + [6] * 14 + [2] * 16
        inputs += [0] * 300
    elif name == "thieves_target":
        # Walk into the walker (the companion launches and floats as a bubble); wait while
        # both thieves race for it, one grabs it and runs to the wall with it and the
        # other gives up; walk on (a stomp defeats the idle one) until the rescue fails.
        # After the respawn, eat the walker and lay an egg, throw it at a thief (struck,
        # a coin), jump in place, then walk up to a thief and lick it (shoved).
        inputs = [0] * 30 + [2] * 60 + [0] * 300 + [2] * 300 + [0] * 400
        inputs += [2] * 25 + [8] + [0] * 30 + [32] + [0] * 40
        inputs += [2] * 36 + [0] * 4 + [64] + [0] * 14 + [64] + [0] * 30
        inputs += [8] + [0] * 30 + [8] + [0] * 30 + ([4] * 14 + [0] * 30) * 4
        inputs += [2] * 58 + ([8] + [0] * 9) * 8 + [0] * 60
    elif name == "spears_target":
        # Lick the right-facing guard from behind (the spear drops; it is caught) and
        # spit it; walk to the egg producer and wait for eggs; throw them and lick at
        # the approaching guard's front (knocks); then hop on through.
        throw = [64] + [0] * 14 + [64] + [0] * 40
        lick = [8] + [0] * 40
        inputs = [0] * 10 + lick * 2 + [2] * 70 + [0] * 300 + throw * 3 + lick * 3
        cycle = [6] * 14 + [2] * 20 + [0] * 10 + lick + [2] * 10
        inputs += cycle * 14 + [2] * 300
    elif name == "armored_target":
        # Wait by the egg producer for eggs, lick the first armored walker (push), throw
        # eggs right (rolls that strike the walkers behind), then walk on hopping and
        # licking through the rest.
        throw = [64] + [0] * 14 + [64] + [0] * 40
        lick = [8] + [0] * 40
        inputs = [0] * 300 + lick * 2 + throw * 4 + [2] * 40 + lick + throw * 2
        cycle = [6] * 14 + [2] * 20 + [0] * 10 + lick + [2] * 10
        inputs += cycle * 16 + [2] * 300
    elif name == "shells_target":
        # Hop right through the shell walkers, landing on them (stomps eject runners and
        # spin empty shells), with a tongue lick and a later spit each cycle.
        cycle = (
            [6] * 14 + [2] * 20 + [0] * 10 + [10] + [0] * 30 + [2] * 10 + [8] + [0] * 20
        )
        inputs = [0] * 30 + cycle * 22 + [2] * 300
    elif name == "switches_target":
        # Hop right onto the one-shot switch (holding JUMP for the high bounce), walk
        # through the toggled block and coin, then hop to the repeating switch and jump
        # straight up to land on it (restarting the interval); wait for it to return
        # when the interval ends and press it again.
        hop = [6] * 14 + [2] * 10 + [0] * 40
        up = [4] * 14 + [0] * 60
        inputs = [2] * 20 + hop + [4] * 30 + [0] * 40 + [2] * 60 + [0] * 300
        inputs += [2] * 30 + hop + up + [0] * 700 + up + [0] * 100 + [2] * 300
    elif name == "flowers_target":
        # Catch the e3 (a spat e3 stays spat; a spat e1 rolls), hop left onto the rock,
        # face right and spit it so it drops into the first flower's cup from above;
        # wait for the releases; walk on to the egg producer, wait for its eggs, and
        # throw them at the second flower's open cup.
        inputs = [0] * 10 + [8] + [0] * 30 + [1] * 8 + [5] * 16 + [0] * 30 + [2] * 2
        inputs += [0] * 10 + [8] + [0] * 560
        inputs += [2] * 70 + [0] * 300
        inputs += ([64] + [0] * 14 + [64] + [0] * 60) * 3 + [2] * 400
    elif name == "stems_target":
        # Wait by the egg producers while they release, ground-pound beside them (the
        # impact starts a burst), collect what lands, walk to the health producer after
        # the walker bumps into Yoshi, and pound there too.
        pound = [4] * 12 + [32] * 30 + [0] * 40
        inputs = (
            [2] * 30 + [0] * 200 + pound + [0] * 120 + [1] * 10 + [2] * 20 + [0] * 60
        )
        inputs += [2] * 120 + [0] * 200 + pound + [0] * 150 + [2] * 400
    elif name == "ledges_target":
        # Hop right onto each ledge, hop in place on it (each landing after leaving it
        # counts one press), and walk off; a walker stands on the last one.
        hop = [6] * 14 + [2] * 10 + [0] * 20
        stay = ([4] * 12 + [0] * 30) * 3
        inputs = ([2] * 20 + hop + stay + [2] * 30 + [0] * 20) * 6 + [2] * 300
    elif name == "gates_target":
        # Bump the egg block for eggs and walk over them, throw them right through gate
        # A's entry side (an egg opens it), walk through A (it closes behind), turn back
        # into its barrier side, jump up into the overhead lid from below, then walk
        # through B and into C's barrier side.
        # The eggs settle on the egg block: step back left and jump onto it (as in
        # hards_target), then walk off to the right.
        bumps = [2] * 22 + ([4] * 10 + [0] * 40) * 3 + [1] * 18 + [0] * 10 + [6] * 16
        bumps += [2] * 6 + [0] * 30 + [2] * 30 + [0] * 20
        throws = ([64] + [0] * 14 + [64] + [0] * 50) * 3
        inputs = bumps + throws + [2] * 100 + [0] * 30 + [1] * 90 + [0] * 10
        inputs += [2] * 80 + [0] * 20 + ([4] * 14 + [0] * 30) * 3 + [2] * 400
    elif name == "grows_target":
        # Walk into the first grow block, stand on it while it rises and holds, wait for
        # it to shrink, then walk on into the next ones (one carries a walker).
        # The blocks hang in the air: head-bump each from below (the touch grows it),
        # then hop up onto the grown block and stand on it until it shrinks.
        hop = [4] * 14 + [0] * 30
        inputs = [2] * 22 + [0] * 10 + hop + [2] * 6 + [6] * 16 + [0] * 400
        inputs += [2] * 40 + [0] * 10 + hop + [0] * 60 + [2] * 60 + [0] * 10 + hop
        inputs += [0] * 60 + [2] * 400
    elif name == "falls_target":
        # Hop up onto each falling span, stand (arm it, ride it down), and in between
        # step off early once to disarm one; then keep walking.
        # The respawning span is 64 px right of the start: jump straight up, drift right
        # at the top, stand to arm it, step off early (disarm), hop back on, ride it down;
        # then step right onto the second span and ride that down too.
        up = [4] * 14 + [6] * 8 + [4] * 6 + [0] * 10
        inputs = (
            up
            + [0] * 30
            + [1] * 10
            + [0] * 40
            + up
            + [0] * 150
            + [0] * 60
            + up
            + [0] * 20
            + [2] * 10
            + [0] * 160
            + [2] * 300
        )
    elif name == "hards_target":
        # Walk under the egg block and bump it four times (the eggs fall and are
        # collected), then aim and throw at the hard blocks, lick one, and push into them.
        # The eggs settle on top of the block: step back left, jump onto the block top to
        # collect them, then walk off to the right before throwing.
        bumps = (
            [2] * 22
            + ([4] * 10 + [0] * 40) * 3
            + [1] * 18
            + [0] * 10
            + [6] * 16
            + [2] * 6
            + [0] * 30
            + [2] * 30
            + [0] * 20
        )
        throws = ([64] + [0] * 14 + [64] + [0] * 50) * 6
        lick = [2] * 30 + [8] + [0] * 40
        inputs = bumps + throws + lick + throws + [2] * 400
    elif name == "flats_target":
        # Walk right hopping onto flat walkers (flatten, stand on the flat body), wait on
        # them, walk off, and ground-pound (jump, then DOWN in the air) every other cycle.
        # First hop in place until the nearest walker (0.8 px a step) arrives under Yoshi.
        wait = ([4] * 12 + [0] * 20) * 14 + [0] * 120
        stomp = [6] * 12 + [2] * 18 + [0] * 40 + [2] * 20
        pound = [6] * 12 + [32] * 30 + [0] * 20 + [2] * 20
        inputs = wait + (stomp + pound) * 10 + [2] * 200
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
