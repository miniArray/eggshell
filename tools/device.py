#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 openssh
"""RG35XX Pro transport. Uses the separately verified, host-key-pinned helper."""

import argparse
import importlib.util
import json
import pathlib
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
REMOTE = "/tmp/eggshell"


def transport():
    helper = pathlib.Path("/tmp/rg35xxpro-delivery/device.py")
    spec = importlib.util.spec_from_file_location("eggshell_transport", helper)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Missing pinned transport: {helper}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.pin()
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=[
            "deploy",
            "trace-tool",
            "pack",
            "level",
            "run",
            "measure",
            "stop",
            "status",
            "fetch",
            "probe",
            "script",
        ],
    )
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    if options.command in {"pack", "level"} and len(options.args) != 1:
        parser.error(f"{options.command} requires one explicit local path")
    link = transport()
    link.run("mkdir", "-p", REMOTE + "/tools")
    if options.command == "deploy":
        status = link.run(
            "bash", REMOTE + "/tools/device-runtime.sh", "status", check=False
        )
        if status.returncode == 0:
            raise RuntimeError("Stop Eggshell before deploying")
        archive = ROOT / "build/eggshell-arm64.tar.gz"
        link.send(archive, REMOTE + "/delivery.tar.gz")
        link.run("tar", "-xzf", REMOTE + "/delivery.tar.gz", "-C", REMOTE)
        result = link.run(
            "bash", REMOTE + "/tools/device-runtime.sh", "setup", check=False
        )
    elif options.command == "trace-tool":
        subprocess.run(
            [sys.executable, str(ROOT / "tools/device-trace-tool.py")], check=True
        )
        link.send(ROOT / "build/trace-tool.tar.gz", REMOTE + "/trace-tool.tar.gz")
        result = link.run(
            "tar", "-xzf", REMOTE + "/trace-tool.tar.gz", "-C", REMOTE, check=False
        )
    elif options.command == "level":
        level = pathlib.Path(options.args[0]).resolve(strict=True)
        if not level.is_file():
            raise RuntimeError("level requires a level-code file")
        status = link.run(
            "bash", REMOTE + "/tools/device-runtime.sh", "status", check=False
        )
        if status.returncode != 3:
            raise RuntimeError("Stop Eggshell before replacing the level")
        link.send(level, REMOTE + "/level.txt")
        link.run("chmod", "0644", REMOTE + "/level.txt")
        print("Installed level: " + REMOTE + "/level.txt")
        return 0
    elif options.command == "pack":
        pack = pathlib.Path(options.args[0])
        if not (pack / "manifest.json").is_file():
            raise RuntimeError("Import the private pack first")
        if json.loads((pack / "manifest.json").read_text()).get("version") != 2:
            raise RuntimeError("Device play requires a version 2 private pack")
        archive = (
            pathlib.Path.home() / ".local/share/eggshell-tools/private-pack.tar.gz"
        )
        archive.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, "w:gz") as output:
            output.add(pack, arcname="external-v2")
        link.send(archive, REMOTE + "/private-pack.tar.gz")
        link.run("mkdir", "-p", REMOTE + "/packs")
        link.run(
            "tar", "-xzf", REMOTE + "/private-pack.tar.gz", "-C", REMOTE + "/packs"
        )
        link.run("chown", "-hR", "korri:korri", REMOTE + "/packs")
        print(
            "Uploaded optional graphics; select with --pack="
            + REMOTE
            + "/packs/external-v2"
        )
        return 0
    elif options.command == "fetch":
        destination = pathlib.Path(
            options.args[0] if options.args else ROOT / "build/device-results"
        )
        destination.mkdir(parents=True, exist_ok=True)
        link.run(
            "tar", "-czf", REMOTE + "/results.tar.gz", "-C", REMOTE, "logs", "write"
        )
        # Use the same pinned SSH options for the reverse transfer.
        archive = destination / "results.tar.gz"
        subprocess.run(
            [
                "scp",
                "-q",
                *link.OPTS,
                "-P",
                "2222",
                f"{link.HOST}:{REMOTE}/results.tar.gz",
                str(archive),
            ],
            check=True,
        )
        with tarfile.open(archive) as source:
            source.extractall(destination, filter="data")
        print(destination)
        return 0
    else:
        if options.command == "probe":
            script, args = ROOT / "tools/device-probe.sh", []
        elif options.command == "script":
            if not options.args:
                parser.error("script requires a local file")
            script, args = pathlib.Path(options.args[0]).resolve(), options.args[1:]
        else:
            script = ROOT / "tools/device-runtime.sh"
            action = "start" if options.command == "run" else options.command
            args = [action, *options.args]
            if options.command == "run" and not options.args:
                args += ["bench", "manual", "60", "opengl3_es"]
        destination = REMOTE + "/tools/" + script.name
        link.send(script, destination)
        link.run("chmod", "0644", destination)
        result = link.run("bash", destination, *args, check=False)
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
