#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
"""Run the public suite using original, repository-owned geometric courses."""

import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(*args):
    print("CHECK:", " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)


def main():
    run("godot", "--version")
    run("nix", "build", ".#godot", "--out-link", "build/godot")
    run("godot", "--headless", "--path", ROOT, "--editor", "--import")
    for name in [
        "collision",
        "pack_manifest",
        "pack_density",
        "screen_plan",
        "terrain_edges",
        "level_format",
        "registry",
        "moves",
        "move_input",
        "life",
        "life_hud",
        "hud_backing",
        "pack_background",
        "enemy_head",
        "foundations",
        "items",
        "platforms",
        "s6_enemies",
        "s6_decor",
        "s6_integration",
        "core",
        "objects",
        "enemies",
        "damage",
    ]:
        run("godot", "--headless", "--path", ".", "--script", f"tests/{name}.gd")
    for blocked in [False, True]:
        with tempfile.TemporaryDirectory() as directory:
            args = [
                "godot",
                "--headless",
                "--path",
                ".",
                "--script",
                "tests/slot.gd",
                "--",
                "--placeholder",
                f"--save-dir={directory}",
                "--level-code=res://tests/fixtures/endurance.level.json",
                "--replay=res://tests/fixtures/endurance.input.json",
            ]
            if blocked:
                args.append("--block-slot-write")
            run(*args)
    run("python3", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v")
    run("python3", "tools/check-runtime.py")
    for directory in ["src", "tests", "bench", "tools"]:
        for script in sorted((ROOT / directory).rglob("*.gd")):
            run(
                "godot",
                "--headless",
                "--path",
                ROOT,
                "--check-only",
                "--script",
                script,
            )
    run("gdlint", "src", "tests", "bench", "tools")
    run("gdformat", "--check", "src", "tests", "bench", "tools")
    run("ruff", "check", "--ignore", "EXE005", "tools", "tests")
    run("ruff", "format", "--check", "tools", "tests")
    scripts = (
        sorted((ROOT / "tools").glob("*.sh"))
        + [ROOT / "tools/play"]
        + sorted((ROOT / "tests").glob("*.sh"))
    )
    run("shellcheck", "--shell=bash", *scripts)
    run("nixfmt", "--check", "flake.nix", *sorted((ROOT / "nix").glob("*.nix")))
    run("nix", "flake", "check", "--no-build", "--all-systems")
    print("FULL_CHECKS PASS", flush=True)


if __name__ == "__main__":
    main()
