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
    elif name == "slimes_target":
        # Lick the first slime; walk under the high ceiling (the hanging slime drips,
        # drops far, lands and stares); hop onto the creeping slime (squash), walk on
        # under the low ceiling and past the others, hopping onto them.
        lick = [8] + [0] * 30
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = [0] * 20 + lick * 2 + [2] * 120 + [0] * 150 + cycle * 30 + [2] * 300
    elif name == "spines_target":
        # Lick the fast spine walker before it reaches Yoshi and swallow it (DOWN lays
        # an egg); walk to the egg producer, wait, and throw eggs at the slow one
        # (raised spines break them and fold); hop on past the one on the ledge.
        lick = [8] + [0] * 20
        throw = [64] + [0] * 14 + [64] + [0] * 40
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = [0] * 50 + [8] + [0] * 60 + [32] + [0] * 60 + [2] * 150 + [0] * 300
        inputs += throw * 5
        inputs += cycle * 30 + [2] * 300
    elif name == "runners_target":
        # Watch the green runner turn between the walls, hop over them and it; wait while
        # the red runner walks into the empty shell; then hop on under the sacks,
        # licking after each hop (the second lantern walker is caught).
        lick = [8] + [0] * 30
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        hop_lick = [6] * 14 + [2] * 20 + [0] * 10 + [8] + [0] * 25
        inputs = (
            [0] * 150 + cycle * 3 + lick * 4 + [0] * 500 + hop_lick * 25 + [2] * 300
        )
    elif name == "hangs_target":
        # Walk under the ceiling, turn back left and lick at the first flyer as it swoops
        # behind (caught), spit it (it flees); hop through the next swoops (landing on
        # some) and on past the flying ones.
        lick = [8] + [0] * 15
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = [2] * 60 + [0] * 20 + [1] * 2 + [0] * 30 + lick * 8 + [0] * 20 + [8]
        inputs += [0] * 60 + cycle * 35 + [2] * 300
    elif name == "spores_target":
        # Lick at the nearest spore while it drifts down to mouth height (swallowed at
        # once); watch the others land and grow into waking sprouts; then hop on
        # through.
        lick = [8] + [0] * 20
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = [0] * 60 + lick * 10 + [0] * 300 + cycle * 35 + [2] * 300
    elif name == "gusts_target":
        # Lick at the first flyer as it arrives (caught) and spit it right (it flies on
        # level); wait for the low flyer to run under Yoshi's feet (a stomp); then hop
        # on past the diagonal, turning and rising flyers.
        lick = [8] + [0] * 20
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = (
            [0] * 10 + lick * 3 + [0] * 20 + [8] + [0] * 200 + cycle * 30 + [2] * 300
        )
    elif name == "bulks_target":
        # Hop onto the first bulk's deck before it leaps (standing squashes it and
        # holds it), ground-pound it, then hop right onto the other decks and pound
        # every other cycle (defeats drop coins and health).
        onto = [6] * 12 + [2] * 6 + [0] * 20
        pound = [4] * 12 + [32] * 30 + [0] * 20
        stomp = [6] * 12 + [2] * 18 + [0] * 40 + [2] * 20
        inputs = onto + [0] * 40 + pound * 2 + (stomp + pound) * 12 + [2] * 300
    elif name == "jugglers_target":
        # Lick the placed hopper before it sinks and spit it at the juggler (thrown: it
        # strikes the tossed hopper); wait while the juggler frowns and grows a new one;
        # then hop on past the placed hoppers and the second juggler.
        lick = [8] + [0] * 30
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = lick * 2 + [0] * 900 + cycle * 30 + [2] * 300
    elif name == "blanks_target":
        # Walk right past every blank placement and coin to the goal.
        inputs = [0] * 10 + [2] * 600
    elif name == "spins_target":
        # Jump into the red switch overhead (the red spans turn), hop right over and onto
        # the spans, strike the blue switch (the blue span turns), then the next red and
        # blue switches while their spans may still be turning.
        hop = [6] * 14 + [2] * 20 + [0] * 10
        inputs = [0] * 10 + [4] * 14 + [0] * 60 + hop * 40 + [2] * 200
    elif name == "hounds_target":
        # The runner kicks the resting egg (playing) and follows; hop back onto its back,
        # face right and ride it through the pool (swimming), up the terrain step
        # (jumping) and on to the far wall; then hop off, throw eggs and walk back.
        inputs = (
            [2] * 60 + [0] * 60 + [1] * 10 + [5] * 10 + [0] * 40 + [2] * 6 + [0] * 600
        )
        inputs += [6] * 14 + [0] * 300 + ([64] + [0] * 14 + [64] + [0] * 60) * 3
        inputs += [1] * 100 + [0] * 300
    elif name == "sprouts_target":
        # Lick the first sprout and spit it right; walk on into the next one; wait by
        # the egg producer and throw eggs right at the approaching one; then hop on
        # through, over the step the last sprout turns at.
        lick = [8] + [0] * 40
        throw = [64] + [0] * 14 + [64] + [0] * 40
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs = [0] * 30 + lick * 2 + [2] * 150 + [0] * 600 + throw * 4
        inputs += cycle * 30 + [2] * 300
    elif name == "launchers_target":
        # Wait for the first straight shot and lick it, spit it back; hop in place until
        # the next shot passes under and is landed on; hop right past the aiming
        # bouncer (its shot overlaps the launcher's own solid and is removed at birth,
        # as in the original) and under the homing launcher.
        lick = [8] + [0] * 40
        inputs = [0] * 90 + lick * 2 + ([4] * 14 + [0] * 30) * 12
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs += cycle * 30 + [2] * 300
    elif name == "wings_target":
        # Lick the bobbing flyer and spit it right into the next one (a strike knock;
        # both turn angry and charge); walk on into the low flyer (from above: a stomp);
        # wait by the egg producer and throw eggs at the calm flyer; then hop on
        # through under the drifting flyer.
        throw = [64] + [0] * 14 + [64] + [0] * 40
        lick = [8] + [0] * 40
        inputs = lick * 2 + [2] * 200 + [0] * 600 + throw * 4
        cycle = [6] * 14 + [2] * 20 + [0] * 10
        inputs += cycle * 20 + [2] * 300
    elif name == "hopstems_target":
        # Stand back while the producer releases hoppers (they fall, hop and sink).
        inputs = [0] * 982
    elif name == "rejoin_target":
        # Walk into the walker (the companion separates into a bubble that drifts right
        # and bobs), hop over the walker, walk ahead of the bubble's low point and lick
        # it; keep pressing and moving during the frozen rejoin.
        inputs = [2] * 60 + [0] * 60 + [6] * 14 + [2] * 10 + [0] * 100
        inputs += [2] * 56 + [0] * 30 + [8] + [0] * 40 + [24] + [0] * 40 + [6] * 20
        inputs += [0] * 200
    elif name == "sceneryledges_target":
        # Hop right from ledge to ledge, landing on each and pausing on it.
        inputs = [0] * 10 + ([6] * 14 + [2] * 8 + [0] * 40) * 18 + [2] * 200
    elif name == "decor_target":
        # Hop onto the plain ledge, then across onto the higher mirrored one, then walk on.
        inputs = [2] * 20 + [6] * 14 + [0] * 100 + [6] * 14 + [2] * 8 + [0] * 100
        inputs += [2] * 300
    elif name == "dice_target":
        # Jump into the first switch from below (group 1 flips: A opens, B closes), walk
        # through A, hop B, bump the egg block for an egg, then throw it at switch 2.
        jump = [4] * 14 + [0] * 50
        throw = [64] + [0] * 14 + [64] + [0] * 60
        inputs = [0] * 10 + [2] * 30 + [0] * 30 + jump + [2] * 90 + [6] * 14 + [2] * 10
        inputs += (
            [0] * 40 + [2] * 24 + [0] * 30 + jump * 2 + [2] * 40 + [0] * 30 + throw
        )
        inputs += [2] * 300
    elif name == "clears_target":
        # Stop under the clear block and jump straight up into it three times.
        jump = [4] * 14 + [0] * 50
        inputs = [0] * 10 + [2] * 30 + [0] * 30 + jump * 3 + [0] * 100 + [2] * 400
    elif name == "balloons_target":
        # Hop onto the slow riser and ride it, jump across to the drifting bobbing one and
        # ride it, then drop off and walk on under the sinking one.
        inputs = [2] * 20 + [6] * 14 + [0] * 200
        inputs += [6] * 14 + [2] * 8 + [0] * 300 + [2] * 400
    elif name == "pillars_target":
        # Walk into the up-pointing pillar's safe side, then hop onto its spike; after
        # the respawn stop under the hanging down-pointing pillar and jump into it.
        inputs = [2] * 60 + [0] * 10 + [4] * 12 + [2] * 14 + [0] * 400
        inputs += [2] * 30 + [0] * 30 + [4] * 14 + [0] * 400
    elif name == "eggblocks_target":
        # Under each egg block jump straight up into it (the bump), wait while it rises,
        # falls and becomes a floating egg, jump again to take the egg, then walk on.
        # Each walk ends at rest, so every jump goes straight up.
        jump = [4] * 14 + [0] * 50
        inputs = [0] * 10 + [2] * 30 + [0] * 30 + jump + jump
        inputs += ([2] * 42 + [0] * 30 + jump + jump) * 3 + [2] * 300
    elif name == "snowtrees_target":
        # Walk and hop through each tree's crown; stand still in one (no puffs).
        hop = [6] * 14 + [2] * 20
        inputs = [2] * 50 + hop * 3 + [0] * 40 + [2] * 40 + hop * 4 + [2] * 60 + hop * 3
        inputs += [2] * 200
    elif name == "ghosts_target":
        lick = [8] + [0] * 30
        inputs = [2] * 30 + [0] * 10 + lick + [2] * 20 + [1] * 12 + [0] * 323 + [2] + [10] + [2] * 18
        inputs += [2] * 130 + [0] * 200 + [2] * 60 + [0] * 200 + [2] * 100 + [0] * 400
    elif name == "discs_target":
        # Walk under the high block's discs, on toward the floor block (its discs come
        # out), back away (they are recalled), come back (out again) and wait.
        inputs = [2] * 200 + [0] * 120 + [1] * 50 + [0] * 120 + [2] * 50 + [0] * 200
        inputs += [2] * 40 + [0] * 120
    elif name == "thorns_target":
        # Jump onto the low bee; lick the fast bee as it comes, spit it, lick it again
        # and swallow it for an egg; throw the egg at the green thorn; lick the walker
        # and spit it at the red thorn; walk into a thorn.
        lick = [8] + [0] * 30
        throw = [64] + [0] * 14 + [64] + [0] * 40
        inputs = [2] * 30 + [0] * 111 + [4] * 14 + [0] * 135
        inputs += [2] * 100 + [0] * 100 + lick * 3 + [32] + [0] * 60
        inputs += [2] * 90 + [0] * 10 + throw + lick * 3 + [8] + [0] * 60
        inputs += [2] * 150 + [0] * 100
    elif name == "elements_target":
        lick = [8] + [0] * 30
        shot = [8] + [0] * 35
        inputs = [2] * 60 + lick * 2 + [0] * 10 + shot * 2
        inputs += [2] * 40 + [0] * 10 + [6] * 14 + [0] * 30 + [2] * 20 + [0] * 80 + [8]
        inputs += [0] * 560 + [2] * 50 + [0] * 5 + lick * 2 + [0] * 10 + shot
        inputs += [2] * 15 + [0] * 5 + shot * 2 + [2] * 120 + [0] * 200
        # Walk on to the element melons: eat the fire melon, shoot, eat the ice melon,
        # shoot three times.
        inputs += lick * 2 + [0] * 60 + shot + [2] * 20 + [0] * 5 + lick * 2
        inputs += shot * 3 + [0] * 100
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
    elif name == "spitters_target":
        # Wait by the egg producer for eggs while the first stem tracks Yoshi and spits,
        # walk closer and throw three eggs (hurt turns, then defeat), lick at the coins,
        # then walk on to the second stem and lick at its falling spikes (one is caught).
        throw = [64] + [0] * 14 + [64] + [0] * 60
        inputs = [2] * 20 + [0] * 560 + [2] * 36 + [0] * 4 + throw * 3
        inputs += ([8] + [0] * 12) * 16 + [0] * 200 + [2] * 130 + ([8] + [0] * 12) * 30
    elif name == "petals_target":
        # Walk up to the first stem while its petals grow and orbit, lick one and spit it
        # (thrown, it strikes the others), ground-pound (the rest drop), back off and
        # wait through the regrowth, the dance and the launch.
        inputs = [0] * 100 + [2] * 50 + [8] + [0] * 30 + [8] + [0] * 30
        inputs += [4] * 12 + [32] * 30 + [0] * 400 + [1] * 20 + [0] * 300
    elif name == "shooters_target":
        # Run up behind the first shooter (it shoots away) and lick it, lay the egg, walk
        # on and throw it at the second (it falls; a pellet hurts on the way), then walk
        # right under the ledge shooter and wait.
        inputs = [0] * 10 + [2] * 64 + [0] * 2 + [8] + [0] * 40 + [32] + [0] * 40
        inputs += [2] * 80 + [64] + [0] * 14 + [64] + [0] * 60 + [2] * 200 + [0] * 200
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
