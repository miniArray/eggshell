#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 nix
"""Pack this checkout and the pinned prebuilt Linux ARM64 runtime (host builds only)."""

import pathlib
import platform
import re
import shutil
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def main():
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise SystemExit("Export on the x86_64 Linux host, never on the target device")
    BUILD.mkdir(exist_ok=True)
    for package, destination in [
        ("godot", "godot"),
        ("runtime-arm64", "runtime-arm64"),
    ]:
        subprocess.run(
            [
                "nix",
                "build",
                f"{ROOT}#{package}",
                "--out-link",
                str(BUILD / destination),
            ],
            check=True,
        )
    stage = BUILD / "project"
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(
        ROOT,
        stage,
        ignore=shutil.ignore_patterns(
            ".git",
            ".godot",
            ".worktree",
            "build",
            "export",
            "result*",
            "__pycache__",
            "packs",
            "results",
        ),
    )
    # Only the built-in pack ships. Never stage other local/private packs.
    shutil.copytree(ROOT / "packs/pantry", stage / "packs/pantry")
    project_file = stage / "project.godot"
    project = project_file.read_text()
    # The starter checkout has no game scene yet. Only the staging copy gets a fallback.
    if "run/main_scene=" not in project:
        project = project.replace(
            "[application]",
            '[application]\n\nrun/main_scene="res://bench/sprites.tscn"',
        )
        project_file.write_text(project)
    godot = str(BUILD / "godot/bin/godot")
    subprocess.run(
        [godot, "--headless", "--path", str(stage), "--editor", "--import"], check=True
    )
    bundle = BUILD / "bundle"
    if bundle.exists():
        for directory in [bundle, *bundle.rglob("*")]:
            if directory.is_dir():
                directory.chmod(0o755)
        shutil.rmtree(bundle)
    bundle.mkdir()
    for name, scene in [
        ("eggshell", None),
        ("sprites", "res://bench/sprites.tscn"),
        ("write-cost", "res://bench/write_cost.tscn"),
    ]:
        contents = project_file.read_text()
        if scene is not None:
            contents = re.sub(
                r"run/main_scene=.*", f'run/main_scene="{scene}"', contents
            )
            contents = re.sub(
                r"window/size/viewport_width=.*",
                "window/size/viewport_width=640",
                contents,
            )
            contents = re.sub(
                r"window/size/viewport_height=.*",
                "window/size/viewport_height=480",
                contents,
            )
        project_file.write_text(contents)
        subprocess.run(
            [
                godot,
                "--headless",
                "--path",
                str(stage),
                "--export-pack",
                "Linux ARM64",
                str(bundle / f"{name}.pck"),
            ],
            check=True,
        )
    shutil.copytree(BUILD / "runtime-arm64", bundle / "runtime", symlinks=False)
    for directory in [bundle / "runtime", bundle / "runtime/lib"]:
        directory.chmod(0o755)
    (bundle / "tools").mkdir()
    for name in [
        "device-runtime.sh",
        "device-probe.sh",
        "device-write-cost.sh",
        "play",
    ]:
        shutil.copy2(ROOT / "tools" / name, bundle / "tools" / name)
    archive = BUILD / "eggshell-arm64.tar.gz"
    with tarfile.open(archive, "w:gz") as output:
        for path in bundle.iterdir():
            output.add(path, arcname=path.name)
    print(archive)


if __name__ == "__main__":
    main()
