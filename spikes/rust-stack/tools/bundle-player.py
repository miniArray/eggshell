#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 patchelf binutils nix
# ruff: noqa: EXE005 -- Nix requires the interpreter directive on line two.
"""Flatten the complete pinned ELF closure and retain its original Nix export.
Only aka executes this. Private assets are copied AFTER the public Nix build.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

assert os.uname().nodename == "aka"
assert os.environ.get("NIX_CONFIG") == "builders ="
package, out = map(Path, sys.argv[1:3])
assert not out.exists(), f"refuse overwrite: {out}"
out.mkdir(parents=True, mode=0o700)
bundle = out / "bundle"
(bundle / "lib").mkdir(parents=True)
(bundle / "bin").mkdir()


def call(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


source = call("git", "rev-parse", "HEAD")
assert source == os.environ["EXPECTED_SOURCE_SHA"]
closure = call("nix-store", "--query", "--requisites", str(package)).splitlines()
(out / "closure.txt").write_text("\n".join(closure) + "\n")
with (out / "runtime-closure.nar").open("wb") as stream:
    subprocess.run(["nix-store", "--export", *closure], check=True, stdout=stream)
provenance = {
    "source": source,
    "package": str(package),
    "nix_config": os.environ["NIX_CONFIG"],
    "closure": closure,
    "files": {},
    "private_assets": {},
    "external_graphics": "Pinned Pro Mesa/panfrost via /run/opengl-driver; actual loaded maps must be archived by parent. Not bundled or established by host build.",
}
# Resolve only the actual ARM64 NEEDED graph, using each original object's
# recorded ordered RUNPATH and the exact interpreter's default glibc directory.
# No Nix-store basename search, executing foreign code, or last-writer overwrite.
original_exe = package / "bin" / "eggshell-spike-player"
loader = Path(call("patchelf", "--print-interpreter", str(original_exe)))
selected = {}
queue = [("eggshell-spike-player", original_exe, "bin"), (loader.name, loader, "lib")]
provenance["dependency_edges"] = []
provenance["dlopen_inputs"] = [
    "libEGL.so.1",
    "libGLESv2.so.2",
    "libudev.so.1",
    "libpulse.so.0",
    "libasound.so.2",
]


def require_arm64(path):
    with path.open("rb") as stream:
        header = stream.read(20)
    assert (
        header[:6] == b"\x7fELF\x02\x01"
        and int.from_bytes(header[18:20], "little") == 183
    ), f"not little-endian ARM64 ELF: {path}"


def resolve_needed(owner, name):
    if "/" in name:
        candidate = Path(name)
        assert candidate.is_absolute() and candidate.is_file(), (
            f"unresolved absolute NEEDED {owner}: {name}"
        )
        return candidate
    runpath = call("patchelf", "--print-rpath", str(owner)).split(":")
    for directory in [*runpath, str(loader.parent)]:
        if not directory:
            continue
        directory = directory.replace("${ORIGIN}", str(owner.parent)).replace(
            "$ORIGIN", str(owner.parent)
        )
        assert "$" not in directory, f"unsupported RUNPATH token: {owner}: {directory}"
        candidate = Path(directory) / name
        if candidate.is_file():
            require_arm64(candidate)
            return candidate
    raise AssertionError(f"unresolved original-RUNPATH dependency {owner}: {name}")


while queue:
    name, original, directory = queue.pop(0)
    original = original.resolve()
    require_arm64(original)
    key = f"{directory}/{name}"
    if key in selected:
        assert digest(selected[key]) == digest(original), (
            f"conflicting resolved runtime dependency {key}: {selected[key]} vs {original}"
        )
        continue
    selected[key] = original
    destination = bundle / key
    shutil.copyfile(original, destination)
    destination.chmod(0o755)
    provenance["files"][key] = {
        "source": str(original),
        "original_sha256": digest(original),
        "original_rpath": call("patchelf", "--print-rpath", str(original)),
    }
    dependencies = call("patchelf", "--print-needed", str(original)).splitlines()
    # SDL dlopens these sonames. Its pinned added RUNPATH admits exact choices.
    if name == "libSDL2-2.0.so.0":
        dependencies += provenance["dlopen_inputs"]
    for dependency in dependencies:
        resolved = resolve_needed(original, dependency)
        provenance["dependency_edges"].append(
            {
                "owner": str(original),
                "needed": dependency,
                "resolved": str(resolved.resolve()),
            }
        )
        queue.append((Path(dependency).name, resolved, "lib"))

licenses = bundle / "licenses"
licenses.mkdir()
shutil.copyfile(
    "spikes/rust-stack/player/native/NOTICE", licenses / "presentation-protocol-NOTICE"
)
sdl_source = selected["lib/libSDL2-2.0.so.0"]
sdl_license = sdl_source.parent.parent / "share/licenses/SDL2/LICENSE.txt"
assert sdl_license.is_file(), "pinned genuine SDL2 license missing"
shutil.copyfile(sdl_license, licenses / "SDL2-LICENSE.txt")
exe = bundle / "bin" / "eggshell-spike-player"
for key in selected:
    path = bundle / key
    if path.name != loader.name:
        subprocess.run(
            [
                "patchelf",
                "--set-rpath",
                "$ORIGIN" if path.parent.name == "lib" else "$ORIGIN/../lib",
                str(path),
            ],
            check=True,
        )
    provenance["files"][key]["bundled_sha256"] = digest(path)
    for dependency in call("patchelf", "--print-needed", str(path)).splitlines():
        assert (bundle / "lib" / Path(dependency).name).exists(), (
            f"missing bundled ELF dependency {dependency} for {path}"
        )

pack = Path.home() / ".local/share/eggshell/packs/original-v3-final"
private = bundle / "private-pack"
private.mkdir(mode=0o700)
inventory_path = Path.home() / "eggshell-remote/player-pack-files.sha256.json"
inventory = json.loads(inventory_path.read_text())
assert len(inventory) == 3028
assert (
    hashlib.sha256(
        json.dumps(inventory, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    == "06f5454b080a43776cc02710411cb8347bf905de6b522b0af254e164be2f8164"
)
shutil.copyfile(inventory_path, private / "pack-files.sha256.json")
manifest = json.loads((pack / "manifest.json").read_text())
files = [
    "manifest.json",
    "drawing_facts.json",
    *[f["file"] for f in manifest["player"]["Idle0"]["frames"]],
]
presentation_bundle = os.environ.get("PLAYER_PRESENTATION_BUNDLE") == "1"
if presentation_bundle:
    stage = (
        Path.home() / "eggshell-remote/artifacts/full-rust-ab/player/presentation-stage"
    )
    for name in [
        f"{name}-asset-bindings.json"
        for name in ["target", "stride", "bounce", "lagoon"]
    ]:
        report = json.loads((stage / name).read_text())
        assert report["mode"] == "asset-binding-only-no-gameplay-no-GPU"
        files.extend(row["file"] for row in report["files"])
    if os.environ.get("PLAYER_REAL_SCREEN_BUNDLE") == "1":
        real = (
            Path.home()
            / "eggshell-remote/artifacts/full-rust-ab/scaling"
            / os.environ.get("REAL_SCREENS_DIR", "real-screens-v2")
        )
        real_report = json.loads((real / "real-assets.json").read_text())
        assert real_report["mode"] == "asset-binding-only-no-gameplay-no-GPU"
        files.extend(row["file"] for row in real_report["files"])
    if os.environ.get("PLAYER_PLAYTEST_BUNDLE") == "1":
        # Every pack music track and effect (audio_player.gd plays them).
        audio = manifest["audio"]
        for entry in [*audio["music"].values(), *audio["effects"].values()]:
            files.append(entry["file"] if isinstance(entry, dict) else entry)
        # Placed and runtime-created codes of the playtest levels (--validate-assets).
        playtest_report = json.loads(
            (
                Path.home()
                / "eggshell-remote/artifacts/full-rust-ab/player/playtest-assets.json"
            ).read_text()
        )
        assert playtest_report["mode"] == "asset-binding-only-no-gameplay-no-GPU"
        files.extend(row["file"] for row in playtest_report["files"])
    if os.environ.get("PLAYER_MIXED_BUNDLE") == "1":
        mixed_report = json.loads(
            (
                Path.home()
                / "eggshell-remote/artifacts/full-rust-ab/scaling/mixed-v2/mixed-asset-bindings.json"
            ).read_text()
        )
        assert mixed_report["mode"] == "asset-binding-only-no-gameplay-no-GPU"
        files.extend(row["file"] for row in mixed_report["files"])
    level_index_path = os.environ.get("LEVEL_INDEX")
    if os.environ.get("PLAYER_PLAYTEST_BUNDLE") == "1" and level_index_path:
        # The level list plays any admitted level, so the whole verified pack ships.
        files.extend(inventory)
    files = sorted(set(files))
for name in files:
    assert not Path(name).is_absolute() and ".." not in Path(name).parts
    target = private / name
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copyfile(pack / name, target)
    target.chmod(0o600)
    provenance["private_assets"][name] = digest(target)
    assert digest(target) == inventory[name], f"private pack inventory mismatch: {name}"

if presentation_bundle:
    inputs = bundle / "private-input"
    inputs.mkdir(mode=0o700)
    sources = {
        "stride.level.json": Path("tests/fixtures/stride.level.json"),
        "stride.input.json": Path("tests/fixtures/stride.input.json"),
        "stride.damage.input.json": Path("tests/fixtures/stride.damage.input.json"),
        "bounce.level.json": Path("tests/fixtures/bounce.level.json"),
        "bounce.input.json": Path("tests/fixtures/bounce.input.json"),
        "bounce.pad.input.json": Path.home()
        / "eggshell-remote/artifacts/full-rust-ab/core/bounce.pad.input.json",
        "lagoon.level.json": Path("tests/fixtures/lagoon.level.json"),
        "lagoon.input.json": Path("tests/fixtures/lagoon.input.json"),
        "collision_table.json": Path("data/collision_table.json"),
        "schema.json": Path.home()
        / "eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json",
        "view-metrics.json": stage / "view-metrics.json",
        "target.level.json": Path.home()
        / ".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json",
    }
    if os.environ.get("PLAYER_SCALING_BUNDLE") == "1":
        scaling = Path.home() / "eggshell-remote/artifacts/full-rust-ab/scaling"
        for name in [
            *[f"scale-{n}.level.json" for n in [25, 50, 100, 200, 400]],
            "idle-1200.input.json",
            "SHA256SUMS",
            "generation.json",
        ]:
            sources[name] = scaling / name
        provenance["benchmark_unverified_level"] = True
        provenance["benchmark_core_tree"] = call(
            "git", "rev-parse", "HEAD:spikes/rust-stack/core"
        )
        launcher = bundle / "launch-owned-scaling"
        shutil.copyfile("spikes/rust-stack/tools/launch-owned-scaling.sh", launcher)
        launcher.chmod(0o755)
        subprocess.run(["shellcheck", "--shell=bash", str(launcher)], check=True)
    if os.environ.get("PLAYER_STRESS_BUNDLE") == "1":
        scaling = Path.home() / "eggshell-remote/artifacts/full-rust-ab/scaling"
        for name in [
            "scale-1600.level.json",
            "scale-2400.level.json",
            "scale-400-dark.level.json",
            "idle-600.input.json",
            "idle-36000.input.json",
            "STRESS-SHA256SUMS",
            "stress-generation.json",
        ]:
            sources[name] = scaling / name
        launcher = bundle / "launch-owned-stress"
        shutil.copyfile("spikes/rust-stack/tools/launch-owned-stress.sh", launcher)
        launcher.chmod(0o755)
        subprocess.run(["shellcheck", "--shell=bash", str(launcher)], check=True)
        provenance["stress_hint_only"] = True
    if os.environ.get("PLAYER_MIXED_BUNDLE") == "1":
        scaling = (
            Path.home() / "eggshell-remote/artifacts/full-rust-ab/scaling/mixed-v2"
        )
        for name in [
            "mix-500.level.json",
            "mix-2000.level.json",
            "mix-500-dark.level.json",
            "wide-400-dark.level.json",
            "MIXED-SHA256SUMS",
            "mixed-generation.json",
        ]:
            sources[name] = scaling / name
        provenance["mixed_benchmark_only"] = True
    if os.environ.get("PLAYER_REAL_SCREEN_BUNDLE") == "1":
        real = (
            Path.home()
            / "eggshell-remote/artifacts/full-rust-ab/scaling"
            / os.environ.get("REAL_SCREENS_DIR", "real-screens-v2")
        )
        levels = sorted(real.glob("real-*.level.json"))
        assert levels
        for path in [
            *levels,
            real / "real-screens-generation.json",
            real / "real-assets.json",
        ]:
            sources[path.name] = path
        provenance["faithful_real_level"] = False
        provenance["real_screen_reconstruction_benchmark_only"] = True
    if os.environ.get("PLAYER_PLAYTEST_BUNDLE") == "1":
        # Godot-matched 7200-step route on the target (oracle/target_route.py).
        sources["target.input.json"] = (
            Path.home() / "eggshell-remote/artifacts/full-rust-ab/core/target.input.json"
        )
        # The original's animated tileset frames (private, from the original game files;
        # never in Git): the player swaps them like the original when present.
        original = Path.home() / ".local/share/eggshell-run/parity/original"
        frames = sorted(original.glob("*tm[0-9]*.png")) if original.is_dir() else []
        if frames:
            tiles = bundle / "private-animated-tiles"
            tiles.mkdir(mode=0o700)
            provenance["animated_tiles"] = {}
            for path in frames:
                target = tiles / path.name
                shutil.copyfile(path, target)
                target.chmod(0o600)
                provenance["animated_tiles"][path.name] = digest(target)
        # Private copies of maps' remote music links (fetch-custom-music.py; never in
        # Git): the player plays a map's {src, dat} music from them when present.
        music = Path.home() / ".local/share/eggshell-run/custom-music"
        if (music / "index.json").is_file():
            music_index = json.loads((music / "index.json").read_text())
            custom = bundle / "private-custom-music"
            (custom / "tracks").mkdir(mode=0o700, parents=True)
            kept = {}
            for url, entry in sorted(music_index.get("tracks", {}).items()):
                name = Path(entry["file"])
                assert name.parent == Path("tracks") and name.suffix == ".ogg", name
                target = custom / name
                shutil.copyfile(music / name, target)
                target.chmod(0o600)
                assert digest(target) == entry["sha256"], f"custom music mismatch: {name}"
                kept[url] = {"file": str(name), "sha256": entry["sha256"]}
            (custom / "index.json").write_text(json.dumps({"tracks": kept}, sort_keys=True))
            (custom / "index.json").chmod(0o600)
            provenance["custom_music"] = {
                "tracks": len(kept),
                "index": digest(custom / "index.json"),
            }
        launcher = bundle / "launch-playtest"
        shutil.copyfile("spikes/rust-stack/tools/launch-playtest.sh", launcher)
        launcher.chmod(0o755)
        subprocess.run(["shellcheck", "--shell=bash", str(launcher)], check=True)
        if level_index_path:
            # Level list (launch-levels): the index of this build and its playable levels.
            corpus = Path(
                os.environ.get("PLAYER_LEVELS_DIR")
                or Path.home() / ".local/share/eggshell-run/corpus/levels"
            )
            index = json.loads(Path(level_index_path).read_text())
            assert index["levels"], "empty level index"
            levels_dir = inputs / "levels"
            levels_dir.mkdir(mode=0o700, parents=True)
            shots = {"gradient": [], "customGradientGenerator": [], "tint": []}
            # One level per drawn part kind, viewed at that placement (--view-at).
            object_shots = {
                c: None
                for c in ["d14", "d27", "d28", "d31", "d39", "d57", "d61", "d75", "p11", "p6"]
            }
            level_digests = {}
            for entry in index["levels"]:
                if not entry["ok"]:
                    continue
                name = entry["file"]
                assert "/" not in name and not name.startswith(".")
                target = levels_dir / name
                shutil.copyfile(corpus / name, target)
                target.chmod(0o600)
                level_digests[name] = digest(target)
                level = json.loads(target.read_text())
                for field, picked in shots.items():
                    if len(picked) < 2 and any(
                        str(m.get(field, "")) not in ("", "0_255,255,255")
                        for m in level.get("maps", {}).values()
                    ):
                        picked.append(name)
                start = level.get("maps", {}).get(
                    "map%d" % int(level.get("startpoint", {}).get("map", 1)), {}
                )
                for obj in start.get("objects", {}).values():
                    code = obj.get("A")
                    if code in object_shots and object_shots[code] is None:
                        if code in ("p11", "p6") and str(obj.get("E2", "")) in ("", "0"):
                            continue
                        object_shots[code] = (name, obj.get("X", 0), obj.get("Y", 0))
            sources["level-index.json"] = Path(level_index_path)
            lines = [f"{n} - - map\n" for n in sorted({n for v in shots.values() for n in v})]
            lines += [
                f"{v[0]} {float(v[1]):g} {float(v[2]):g} {c}\n"
                for c, v in object_shots.items()
                if v is not None
            ]
            (inputs / "level-shots.txt").write_text("".join(lines))
            provenance["level_list"] = {
                "levels": len(index["levels"]),
                "playable": sum(e["ok"] for e in index["levels"]),
                "shots": shots,
                "object_shots": object_shots,
                "files": level_digests,
            }
            sources["idle-600.input.json"] = (
                Path.home() / "eggshell-remote/artifacts/full-rust-ab/scaling/idle-600.input.json"
            )
            launcher = bundle / "launch-levels"
            shutil.copyfile("spikes/rust-stack/tools/launch-levels.sh", launcher)
            launcher.chmod(0o755)
            subprocess.run(["shellcheck", "--shell=bash", str(launcher)], check=True)
    provenance["private_inputs"] = {}
    for name, source_path in sources.items():
        target = inputs / name
        shutil.copyfile(source_path, target)
        target.chmod(0o600)
        provenance["private_inputs"][name] = {
            "source": str(source_path),
            "sha256": digest(target),
        }
    assert (
        digest(inputs / "target.level.json")
        == "bbe93d1592bcb6b9576c908ceae50518d42b031cf3f1997486a37daf4a062a17"
    )
    owned = bundle / "launch-owned-verify"
    owned.write_text("""#!/run/current-system/sw/bin/bash
set -euo pipefail
unset LD_LIBRARY_PATH
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
declare +x LIBPATH="$ROOT/lib:/run/opengl-driver/lib"
export XKB_CONFIG_ROOT="$ROOT/xkb"
if [[ -f "$ROOT/locale/en_US.UTF-8/Compose" ]]; then
  export XLOCALEDIR="$ROOT/locale"
  export XCOMPOSEFILE="$ROOT/locale/en_US.UTF-8/Compose"
fi
export SDL_VIDEODRIVER=wayland SDL_AUDIODRIVER=dummy SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0
exec "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" --play \\
  --level "$ROOT/private-input/stride.level.json" --collision "$ROOT/private-input/collision_table.json" \\
  --schema "$ROOT/private-input/schema.json" --pack-root "$ROOT/private-pack" \\
  --pack-inventory "$ROOT/private-pack/pack-files.sha256.json" --view-metrics "$ROOT/private-input/view-metrics.json" \\
  --replay "$ROOT/private-input/stride.input.json" --ticks 120 --seconds 30 \\
  --save-dir "$ROOT/data/saves" --capture-tick 120 --capture "$ROOT/data/owned-tick-120.png" "$@"
""")
    owned.chmod(0o755)
    owned_source = owned.read_text()
    assert "export LD_LIBRARY_PATH" not in owned_source
    assert "| tee" not in owned_source and "\\ngrep " not in owned_source
    assert (
        'exec "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH"'
        in owned_source
    )
    subprocess.run(["shellcheck", "--shell=bash", str(owned)], check=True)
    cases = bundle / "launch-owned-case"
    cases.write_text("""#!/run/current-system/sw/bin/bash
set -euo pipefail
unset LD_LIBRARY_PATH
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
declare +x LIBPATH="$ROOT/lib:/run/opengl-driver/lib"
export XKB_CONFIG_ROOT="$ROOT/xkb"
if [[ -f "$ROOT/locale/en_US.UTF-8/Compose" ]]; then
  export XLOCALEDIR="$ROOT/locale"
  export XCOMPOSEFILE="$ROOT/locale/en_US.UTF-8/Compose"
fi
export SDL_VIDEODRIVER=wayland SDL_AUDIODRIVER=dummy SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0
fixture=${1:?usage: launch-owned-case FIXTURE INPUT_CALLS}
calls=${2:?usage: launch-owned-case FIXTURE INPUT_CALLS}
shift 2
case "$fixture" in stride|stride.damage|bounce|bounce.pad|lagoon) ;; *) printf 'Unknown fixture: %s\\n' "$fixture" >&2; exit 2 ;; esac
[[ "$calls" =~ ^[1-9][0-9]{0,2}$ && "$calls" -le 800 ]]
base=${fixture%%.*}
printf 'RUST_FIXTURE_CAPTURE_CASE fixture=%s input_calls=%s capture_tainted=true target_A_B_claim=false\\n' "$fixture" "$calls"
exec "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" --play \\
  --level "$ROOT/private-input/$base.level.json" --collision "$ROOT/private-input/collision_table.json" \\
  --schema "$ROOT/private-input/schema.json" --pack-root "$ROOT/private-pack" \\
  --pack-inventory "$ROOT/private-pack/pack-files.sha256.json" --view-metrics "$ROOT/private-input/view-metrics.json" \\
  --replay "$ROOT/private-input/$fixture.input.json" --ticks "$calls" --seconds 30 \\
  --save-dir "$ROOT/data/saves" --capture-tick "$calls" --capture "$ROOT/data/$fixture-call-$calls.png" "$@"
""")
    cases.chmod(0o755)
    subprocess.run(["shellcheck", "--shell=bash", str(cases)], check=True)
    provenance["owned_verify_scope"] = (
        "120 actual authoritative Stride calls or named admitted fixture call1..800, original pack, owned GLES; target gameplay remains refused; not a clean performance run"
    )

blend_probe = bundle / "launch-blend-probe"
blend_probe.write_text("""#!/run/current-system/sw/bin/bash
set -euo pipefail
unset LD_LIBRARY_PATH
ROOT=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
declare +x LIBPATH="$ROOT/lib:/run/opengl-driver/lib"
export XKB_CONFIG_ROOT="$ROOT/xkb"
export SDL_VIDEODRIVER=wayland SDL_AUDIODRIVER=dummy SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0
exec "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LIBPATH" "$ROOT/bin/eggshell-spike-player" --blend-probe "$ROOT/data/blend-default.png" "$ROOT/data/blend-default.json" "$@"
""")
blend_probe.chmod(0o755)
subprocess.run(["shellcheck", "--shell=bash", str(blend_probe)], check=True)

# xkbcommon's default Nix path is not relocatable. Retain the closure's keyboard data.
for store in closure:
    xkb = Path(store) / "share/X11/xkb"
    if xkb.is_dir():
        shutil.copytree(xkb, bundle / "xkb", symlinks=False)
        break
# xkbcommon Compose is a separate locale resource, not an ELF dependency.
# Preserve one exact content-verified copy from the pinned full Nix closure.
locale_roots = [
    Path(store) / "share/X11/locale"
    for store in closure
    if (Path(store) / "share/X11/locale/en_US.UTF-8/Compose").is_file()
]
if locale_roots:
    inventories = []
    for root in locale_roots:
        inventory = {
            str(p.relative_to(root)): digest(p)
            for p in sorted(root.rglob("*"))
            if p.is_file()
        }
        inventories.append(inventory)
    assert all(i == inventories[0] for i in inventories), (
        "conflicting Compose locale resources in pinned closure"
    )
    shutil.copytree(locale_roots[0], bundle / "locale", symlinks=False)
    provenance["locale_resources"] = {
        "sources": [str(p) for p in locale_roots],
        "files": inventories[0],
    }
else:
    provenance["locale_resources"] = {
        "text_input": "not admitted: Compose data not present in runtime closure; controller/key controls do not use text entry"
    }
launch = bundle / "launch-smoke"
launch.write_text("""#!/run/current-system/sw/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$ROOT/lib:/run/opengl-driver/lib"
export XKB_CONFIG_ROOT="$ROOT/xkb"
if [[ -f "$ROOT/locale/en_US.UTF-8/Compose" ]]; then
  export XLOCALEDIR="$ROOT/locale"
  export XCOMPOSEFILE="$ROOT/locale/en_US.UTF-8/Compose"
fi
export SDL_VIDEODRIVER=wayland SDL_RENDER_DRIVER=opengles2 SDL_AUDIODRIVER=dummy
export SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=0
exec "$ROOT/lib/ld-linux-aarch64.so.1" --library-path "$LD_LIBRARY_PATH" "$ROOT/bin/eggshell-spike-player" --pack-root "$ROOT/private-pack" --pack-inventory "$ROOT/private-pack/pack-files.sha256.json" --seconds 10 "$@"
""")
launch.chmod(0o755)
provenance["toolchain"] = (
    Path("spikes/rust-stack/player/rust-toolchain.toml")
).read_text()
provenance["cargo_lock_sha256"] = digest(Path("spikes/rust-stack/player/Cargo.lock"))
provenance["flake_lock_sha256"] = digest(Path("spikes/rust-stack/player/flake.lock"))
provenance["flags"] = (
    "Cargo release, thin LTO, codegen-units=1, panic=abort; aarch64-unknown-linux-gnu; no target-cpu override"
)
(out / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
shutil.copyfile(out / "provenance.json", bundle / "provenance.json")
subprocess.run(
    ["tar", "-czf", str(out / "smoke-arm64.tar.gz"), "-C", str(bundle), "."], check=True
)
(out / "SHA256SUMS").write_text(
    "".join(
        f"{digest(path)}  {path.name}\n"
        for path in [
            out / "smoke-arm64.tar.gz",
            out / "runtime-closure.nar",
            out / "provenance.json",
        ]
    )
)
print((out / "SHA256SUMS").read_text(), end="")
print(
    f"RUST_SMOKE_BUNDLE source={source} path={out} bytes={(out / 'smoke-arm64.tar.gz').stat().st_size}"
)
