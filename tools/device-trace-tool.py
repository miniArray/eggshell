#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 nix patchelf
"""Bundle cached ARM64 strace on the host; never build or install on the target."""

import pathlib
import platform
import shutil
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise SystemExit(
            "Prepare tracing tools on the x86_64 Linux host, never on the device"
        )
    expression = (
        f'(import (builtins.getFlake "{ROOT}").inputs.nixpkgs '
        '{ system = "aarch64-linux"; }).strace.outPath'
    )
    source = pathlib.Path(
        output("nix", "eval", "--impure", "--raw", "--expr", expression)
    )
    # Copy from the binary cache explicitly. A cache miss fails, never builds.
    subprocess.run(
        ["nix", "copy", "--from", "https://cache.nixos.org", str(source)], check=True
    )
    closure = output("nix-store", "--query", "--requisites", str(source)).splitlines()
    libraries = {}
    for package in closure:
        for library in pathlib.Path(package, "lib").glob("*.so*"):
            if library.is_file():
                libraries.setdefault(library.name, library)
    stage = ROOT / "build/trace-tool"
    if stage.exists():
        shutil.rmtree(stage)
    (stage / "lib").mkdir(parents=True)
    executable = stage / "strace"
    shutil.copyfile(source / "bin/strace", executable)
    executable.chmod(0o755)
    pending = output("patchelf", "--print-needed", str(executable)).splitlines()
    copied = set()
    runtime = ROOT / "build/runtime-arm64/lib"
    while pending:
        name = pending.pop()
        if name in copied or (runtime / name).exists():
            continue
        original = libraries[name]
        target = stage / "lib" / name
        shutil.copyfile(original, target)
        target.chmod(0o755)
        pending.extend(output("patchelf", "--print-needed", str(target)).splitlines())
        subprocess.run(
            [
                "patchelf",
                "--set-rpath",
                "$ORIGIN:/tmp/eggshell/runtime/lib",
                str(target),
            ],
            check=True,
        )
        copied.add(name)
    subprocess.run(
        [
            "patchelf",
            "--set-interpreter",
            "/tmp/eggshell/runtime/lib/ld-linux-aarch64.so.1",
            "--set-rpath",
            "$ORIGIN/lib:/tmp/eggshell/runtime/lib",
            str(executable),
        ],
        check=True,
    )
    archive = ROOT / "build/trace-tool.tar.gz"
    with tarfile.open(archive, "w:gz") as destination:
        destination.add(stage, arcname="trace-tool")
    print(f"Cached tool: {source}; libraries: {sorted(copied)}; archive: {archive}")


if __name__ == "__main__":
    main()
