#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i python3
# ruff: noqa: EXE005 -- nix-shell requires a second shebang directive.
"""Make a private oracle-only counter overlay. Never edit the source checkout.

Every change adds read-only workload counters outside PlayState. The source
baseline and exact patch hashes are recorded for independent inspection.
"""

import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path


def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise RuntimeError(f"Instrumentation seam changed: {path}: {before!r}")
    path.write_text(text.replace(before, after))


def main():
    if socket.gethostname() != "aka" or "builders =" not in os.environ.get(
        "NIX_CONFIG", ""
    ):
        raise SystemExit(
            "Oracle overlays run only on aka with remote builders disabled"
        )
    source = Path.cwd()
    destination = Path(sys.argv[1]).resolve()
    private_root = Path.home() / "eggshell-remote/artifacts/full-rust-ab/core"
    if private_root not in destination.parents:
        raise SystemExit("Overlay must be under the private core artifact root")
    subprocess.run(
        [
            "git",
            "diff",
            "--exit-code",
            "297ada9a022d0ddc297dd2d4091c5dccfab4531e",
            "--",
            "src",
            "tests/fixtures",
        ],
        check=True,
    )
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "project.godot", destination / "project.godot")
    for directory in ["src", "tests", "art", "packs"]:
        shutil.copytree(source / directory, destination / directory, dirs_exist_ok=True)
    scripts = destination / "spikes/rust-stack/oracle"
    scripts.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "spikes/rust-stack/oracle/export.gd", scripts / "export.gd")
    registry = destination / "src/sim/registry.gd"
    dispatch = destination / "src/sim/dispatch_loops.gd"
    collision = destination / "src/sim/collision.gd"
    world = destination / "src/sim/world.gd"
    replace_once(
        registry,
        "extends RefCounted\n",
        "extends RefCounted\nstatic var spike_nearby_queries: int = 0\nstatic var spike_spawns: int = 0\n",
    )
    replace_once(
        registry,
        "static func nearby(state: Dictionary, world: Dictionary, box: Array) -> Array:\n",
        "static func nearby(state: Dictionary, world: Dictionary, box: Array) -> Array:\n\tspike_nearby_queries += 1\n",
    )
    replace_once(
        registry,
        "\tstate.entities.append(entity)\n\tattach_views(state)\n\treturn entity\n",
        "\tstate.entities.append(entity)\n\tspike_spawns += 1\n\tattach_views(state)\n\treturn entity\n",
    )
    replace_once(
        dispatch,
        "extends RefCounted\n",
        "extends RefCounted\nstatic var spike_steps: int = 0\nstatic var spike_contacts: int = 0\nstatic var spike_steps_by_code: Dictionary = {}\n",
    )
    replace_once(
        dispatch,
        "\t\t\t\tknown.type.step(entity, state, world)\n",
        "\t\t\t\tspike_steps += 1\n\t\t\t\tspike_steps_by_code[entity.code] = spike_steps_by_code.get(entity.code, 0) + 1\n\t\t\t\tknown.type.step(entity, state, world)\n",
    )
    replace_once(
        dispatch,
        "\t\t\t\tknown.type.contact(entity, state, world, input)\n",
        "\t\t\t\tspike_contacts += 1\n\t\t\t\tknown.type.contact(entity, state, world, input)\n",
    )
    replace_once(
        collision,
        "extends RefCounted\n",
        "extends RefCounted\nstatic var spike_solid_queries: int = 0\n",
    )
    replace_once(
        collision,
        "static func _shapes(world: Dictionary, left: int, top: int, right: int, bottom: int) -> Array:\n",
        "static func _shapes(world: Dictionary, left: int, top: int, right: int, bottom: int) -> Array:\n\tspike_solid_queries += 1\n",
    )
    replace_once(
        world,
        "extends RefCounted\n",
        "extends RefCounted\nstatic var spike_terrain_queries: int = 0\n",
    )
    replace_once(
        world,
        "static func tiles_overlap_box(\n\tworld: Dictionary, left: int, top: int, right: int, bottom: int\n) -> bool:\n",
        "static func tiles_overlap_box(\n\tworld: Dictionary, left: int, top: int, right: int, bottom: int\n) -> bool:\n\tspike_terrain_queries += 1\n",
    )
    records = []
    for path in [registry, dispatch, collision, world]:
        relative = path.relative_to(destination)
        records.append(
            {
                "path": str(relative),
                "baseline_sha256": hashlib.sha256(
                    (source / relative).read_bytes()
                ).hexdigest(),
                "instrumented_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )
    (destination / "overlay.json").write_text(
        json.dumps(
            {
                "baseline": "297ada9a022d0ddc297dd2d4091c5dccfab4531e",
                "changes": records,
                "purpose": "Counters only; no saved-state or gameplay changes",
            },
            indent=2,
        )
        + "\n"
    )
    print(f"ORACLE_OVERLAY_DONE path={destination}", flush=True)


if __name__ == "__main__":
    main()
