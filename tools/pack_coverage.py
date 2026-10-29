#!/usr/bin/env python3
"""Graphics coverage of one pack over a set of level codes.

The engine decides what it draws. `tools/pack_coverage.gd` builds the game's own
level view for each map and reports, per slot, whether the pack fills it, the view
falls back to a placeholder, or the engine has no object type. This script runs that
runner, adds the cross-level summary and ranking, and writes JSON and Markdown.

    python3 tools/pack_coverage.py --pack ~/.local/share/eggshell/packs/verdigris-wip-3a \
        --reference ~/.local/share/eggshell/packs/original-v3-local \
        --json out.json --markdown out.md LEVEL...
"""

import argparse
import datetime
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = "res://tools/pack_coverage.gd"
KINDS = ["tileset", "background", "gradient", "object", "player"]
PACK_WIDE = ["hud", "scenery", "runtime"]
STATUSES = ["pack", "fallback", "engine-missing", "level"]
GROUPS = {"e": "enemy", "o": "object", "p": "platform", "d": "decoration"}


class CoverageError(Exception):
    """The engine runner failed or returned unusable facts."""


def find_godot(explicit=None):
    for candidate in [
        explicit,
        os.environ.get("EGGSHELL_ENGINE"),
        shutil.which("godot"),
        ROOT / "build/godot/bin/godot",
    ]:
        if candidate and pathlib.Path(candidate).exists():
            return str(candidate)
    raise CoverageError(
        "No Godot binary: pass --godot, set EGGSHELL_ENGINE, or run inside `nix develop`"
    )


def run_engine(godot, pack, levels):
    """Facts from the GDScript runner. Paths are absolute so the project root does not matter."""
    with tempfile.TemporaryDirectory() as directory:
        out = pathlib.Path(directory) / "facts.json"
        command = [
            godot,
            "--headless",
            "--path",
            str(ROOT),
            "--script",
            RUNNER,
            "--",
            f"--pack={pack}",
            f"--out={out}",
            *[f"--level={level}" for level in levels],
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if not out.exists():
            raise CoverageError(
                f"Runner wrote no facts (exit {result.returncode}):\n{result.stderr[-4000:]}"
            )
        facts = json.loads(out.read_text())
    errors = [level for level in facts["levels"] if "error" in level]
    if result.returncode != 0 and not errors:
        raise CoverageError(
            f"Runner failed (exit {result.returncode}):\n{result.stderr[-4000:]}"
        )
    return facts


def labels(reference):
    """Human names for object codes, from a reference pack's imported `source_type`."""
    if reference is None:
        return {}
    manifest = json.loads((pathlib.Path(reference) / "manifest.json").read_text())
    result = {}
    for code, entry in manifest.get("objects", {}).items():
        if isinstance(entry, dict) and isinstance(entry.get("source_type"), str):
            result[code] = entry["source_type"]
    return result


def reference_poses(reference):
    if reference is None:
        return []
    manifest = json.loads((pathlib.Path(reference) / "manifest.json").read_text())
    return sorted(manifest.get("player", {}))


def group(kind, slot_id):
    if kind != "object":
        return kind
    return GROUPS.get(slot_id[:1], "engine") + (
        " head" if slot_id.endswith("_head") else ""
    )


def summarize(facts, counted, names=None, poses=None, top=15):
    """Pure: per-kind totals and the ranked missing slots over the counted level files."""
    names = names or {}
    counted = set(counted)
    levels = [level for level in facts["levels"] if "error" not in level]
    tally = {}
    for level in levels:
        if level["file"] not in counted:
            continue
        for slot in level["slots"]:
            key = (slot["kind"], slot["id"], slot["status"])
            entry = tally.setdefault(
                key,
                {
                    "kind": slot["kind"],
                    "id": slot["id"],
                    "group": group(slot["kind"], slot["id"]),
                    "label": names.get(slot["id"].removesuffix("_head"), ""),
                    "status": slot["status"],
                    "levels": 0,
                    "instances": 0,
                    "details": {},
                },
            )
            entry["levels"] += 1
            entry["instances"] += slot["instances"]
            for detail, count in slot["details"].items():
                entry["details"][detail] = entry["details"].get(detail, 0) + count
    totals = {}
    for kind in KINDS:
        row = {status: {"slots": 0, "uses": 0, "instances": 0} for status in STATUSES}
        for entry in tally.values():
            if entry["kind"] == kind:
                cell = row[entry["status"]]
                cell["slots"] += 1
                cell["uses"] += entry["levels"]
                cell["instances"] += entry["instances"]
        totals[kind] = row
    groups = {}
    for entry in tally.values():
        if entry["kind"] == "object":
            cell = groups.setdefault(entry["group"], {status: 0 for status in STATUSES})
            cell[entry["status"]] += entry["instances"]

    def with_feature(name, test=bool):
        return [
            level["name"]
            for level in levels
            if level["file"] in counted and test(level["features"][name])
        ]

    def rank(entry):
        return (-entry["levels"], -entry["instances"], entry["kind"], entry["id"])

    missing = sorted((e for e in tally.values() if e["status"] == "fallback"), key=rank)
    absent = sorted(
        (e for e in tally.values() if e["status"] == "engine-missing"), key=rank
    )
    requested = set(facts["engine_poses"]["dry"]) | set(facts["engine_poses"]["water"])
    return {
        "counted_levels": sorted(counted & {level["file"] for level in levels}),
        "totals": totals,
        "object_groups": groups,
        "slots": sorted(tally.values(), key=rank),
        "missing": missing,
        "top_missing": missing[:top],
        "top_missing_per_kind": {
            kind: [e for e in missing if e["kind"] == kind][:5] for kind in KINDS
        },
        "engine_missing": absent,
        "pack_wide": {kind: facts[kind] for kind in PACK_WIDE},
        "mechanics": {
            "reference_poses_never_requested": [
                p for p in (poses or []) if p not in requested
            ],
            "levels_with_water": with_feature("water"),
            "levels_with_lava": with_feature("lava"),
            "levels_with_several_maps": with_feature("maps", lambda maps: maps > 1),
        },
    }


def short(path):
    """Paths under the home folder print with `~`, so reports do not embed the user name."""
    return str(path).replace(str(pathlib.Path.home()), "~", 1)


def coverage(row, unit):
    filled = row["pack"][unit]
    needed = filled + row["fallback"][unit]
    return f"{100 * filled / needed:.0f}%" if needed else "n/a"


def detail_text(details, limit=3):
    ordered = sorted(details, key=lambda d: (-details[d], d))
    text = "; ".join(ordered[:limit])
    return text + (f"; +{len(ordered) - limit} more" if len(ordered) > limit else "")


def markdown(report):
    facts = report["facts"]
    summary = report["summary"]
    lines = [
        f"# Graphics coverage: {pathlib.Path(facts['pack']).name}",
        "",
        f"Generated {report['generated']} by `tools/pack_coverage.py` at commit"
        f" `{report['commit']}`. Pack: `{short(facts['pack'])}` (density {facts['density']}"
        + (
            ""
            if facts["pack_loaded"]
            else ", **not loadable: the game draws placeholders**"
        )
        + ").",
        "",
        f"Command: `{report['command']}`",
        "",
        (
            "Statuses: `pack` = the pack draws it; `fallback` = the view draws a placeholder"
            " (diagnostic square, default pose, or nothing for backgrounds); `engine-missing` ="
            " no engine type for this code or form, so art does not help; `level` = the level"
            " code itself supplies it (custom gradient strips)."
        ),
        "",
        f"Counted levels: {len(summary['counted_levels'])}. Uses = slot x level pairs.",
        "",
        "## Coverage per kind",
        "",
        (
            "| Kind | Slots pack | Slots fallback | Slots engine-missing | Slot coverage"
            " | Uses coverage | Instances pack / fallback / engine-missing |"
        ),
        "| --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for kind, row in summary["totals"].items():
        lines.append(
            f"| {kind} | {row['pack']['slots']} | {row['fallback']['slots']}"
            f" | {row['engine-missing']['slots']} | {coverage(row, 'slots')}"
            f" | {coverage(row, 'uses')} | {row['pack']['instances']} /"
            f" {row['fallback']['instances']} / {row['engine-missing']['instances']} |"
        )
    lines += [
        "",
        "Object instances by group (pack / fallback / engine-missing):",
        "",
    ]
    for name, cell in sorted(summary["object_groups"].items()):
        lines.append(
            f"- {name}: {cell['pack']} / {cell['fallback']} / {cell['engine-missing']}"
        )
    top = summary["top_missing"]
    lines += [
        "",
        f"## Top {len(top)} missing slots",
        "",
        (
            "Ranked by levels that use the slot, then by instances (cells for tilesets,"
            " placements for objects, one per level for other kinds). "
            f"All {len(summary['missing'])} are in the JSON."
        ),
        "",
        "Name is the type name in the reference pack, when one is given.",
        "",
        "| # | Kind | Slot | Name | Levels | Instances | Drawn as |",
        "| ---: | --- | --- | --- | ---: | ---: | --- |",
    ]
    for index, entry in enumerate(top, 1):
        lines.append(
            f"| {index} | {entry['group']} | `{entry['id']}` | {entry['label']}"
            f" | {entry['levels']} | {entry['instances']} | {detail_text(entry['details'])} |"
        )
    lines += [
        "",
        "Top missing slots per kind:",
        "",
    ]
    for kind, entries in summary["top_missing_per_kind"].items():
        shown = ", ".join(
            f"`{e['id']}`"
            + (f" {e['label']}" if e["label"] else "")
            + f" ({e['levels']} levels, {e['instances']})"
            for e in entries
        )
        lines.append(f"- {kind}: {shown or 'none'}")
    lines += ["", "## Engine-missing objects", ""]
    if summary["engine_missing"]:
        lines += [
            "| Code | Name | Levels | Instances | Reason |",
            "| --- | --- | ---: | ---: | --- |",
        ]
        for entry in summary["engine_missing"]:
            lines.append(
                f"| `{entry['id']}` | {entry['label']} | {entry['levels']}"
                f" | {entry['instances']} | {detail_text(entry['details'])} |"
            )
    else:
        lines.append("None.")
    lines += [
        "",
        "## Pack-wide slots",
        "",
        "| Kind | Slot | Status | Drawn as |",
        "| --- | --- | --- | --- |",
    ]
    for kind in PACK_WIDE:
        for slot in summary["pack_wide"][kind]:
            lines.append(
                f"| {kind} | `{slot['id']}` | {slot['status']} | {slot['detail']} |"
            )
    mechanics = summary["mechanics"]
    poses = facts["engine_poses"]
    lines += [
        "",
        "## Player mechanics",
        "",
        (
            f"The pose selector (`src/view/player_pose.gd`) returns {len(poses['dry'])} names"
            f" out of water and {len(poses['water'])} more in water (seeded sweep of"
            f" {facts['pose_sweep']['samples']} states; rarest name hit {poses['rarest_hits']} times)."
        ),
        "",
        "- Levels with water (swim poses counted): "
        + (", ".join(mechanics["levels_with_water"]) or "none"),
        "- Levels with lava: " + (", ".join(mechanics["levels_with_lava"]) or "none"),
        "- Levels with more than one map (map travel is not implemented): "
        + (", ".join(mechanics["levels_with_several_maps"]) or "none"),
        "- Reference-pack player animations the engine never requests: "
        + (
            ", ".join(f"`{p}`" for p in mechanics["reference_poses_never_requested"])
            or "none"
        ),
    ]
    for note in report.get("notes", []):
        lines += ["", note.rstrip()]
    lines += ["", "## Per level", ""]
    counted = set(summary["counted_levels"])
    for level in facts["levels"]:
        title = level.get("name", pathlib.Path(level["file"]).name)
        tag = "" if level["file"] in counted else " (test course, not counted)"
        lines += [f"### {title}{tag}", "", f"`{short(level['file'])}`", ""]
        if "error" in level:
            lines += [f"Error: {level['error']}", ""]
            continue
        for kind in KINDS:
            parts = []
            for status in ["pack", "fallback", "engine-missing", "level"]:
                ids = [
                    s
                    for s in level["slots"]
                    if s["kind"] == kind and s["status"] == status
                ]
                if not ids:
                    continue
                if kind == "player":
                    parts.append(f"{status} {len(ids)}")
                    continue
                ids.sort(key=lambda s: (-s["instances"], s["id"]))
                shown = ", ".join(
                    f"`{s['id']}`"
                    + (f" x{s['instances']}" if s["instances"] > 1 else "")
                    for s in ids
                )
                parts.append(f"{status}: {shown}")
            if parts:
                lines.append(f"- {kind}: " + "; ".join(parts))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def commit():
    result = subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() or "unknown"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pack", required=True, help="graphics pack directory")
    parser.add_argument(
        "levels", nargs="*", help="level code files counted in the summary"
    )
    parser.add_argument(
        "--test-course",
        action="append",
        default=[],
        help="level listed per level but left out of the summary (repeatable)",
    )
    parser.add_argument(
        "--reference",
        help="pack whose object names label codes, e.g. the original pack",
    )
    parser.add_argument(
        "--notes",
        action="append",
        default=[],
        help="Markdown file appended after the mechanics section (repeatable)",
    )
    parser.add_argument("--json", help="write the JSON report here")
    parser.add_argument("--markdown", help="write the Markdown report here")
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--godot")
    args = parser.parse_args(argv)
    pack = pathlib.Path(args.pack).expanduser()
    if not (pack / "manifest.json").is_file():
        parser.error(f"not a pack (no manifest.json): {pack}")
    levels = [str(pathlib.Path(p).expanduser().resolve()) for p in args.levels]
    courses = [str(pathlib.Path(p).expanduser().resolve()) for p in args.test_course]
    if not levels and not courses:
        parser.error("give at least one level file")
    for path in levels + courses:
        if not pathlib.Path(path).is_file():
            parser.error(f"level file not found: {path}")
    try:
        facts = run_engine(find_godot(args.godot), pack.resolve(), levels + courses)
    except CoverageError as error:
        print(f"pack_coverage: {error}", file=sys.stderr)
        return 2
    report = {
        "generated": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%d %H:%M UTC"),
        "commit": commit(),
        "command": " ".join(
            ["tools/pack_coverage.py", *(argv if argv is not None else sys.argv[1:])]
        ).replace(str(pathlib.Path.home()), "~"),
        "summary": summarize(
            facts,
            levels,
            labels(args.reference),
            reference_poses(args.reference),
            args.top,
        ),
        "facts": facts,
    }
    report["notes"] = [pathlib.Path(note).read_text() for note in args.notes]
    text = markdown(report)
    if args.json:
        pathlib.Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(args.json).write_text(json.dumps(report, indent=1) + "\n")
    if args.markdown:
        pathlib.Path(args.markdown).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(args.markdown).write_text(text)
    if not args.json and not args.markdown:
        sys.stdout.write(text)
    errors = [level for level in facts["levels"] if "error" in level]
    for level in errors:
        print(f"pack_coverage: {level['file']}: {level['error']}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
