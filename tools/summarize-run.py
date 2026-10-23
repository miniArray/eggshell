#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
"""Recompute frame, script/monitor, and worker-save costs from a fetched run."""

import argparse
import csv
import json
import math
import pathlib
import statistics


def stats(values):
    ordered = sorted(values)
    if not ordered:
        return {"count": 0}
    result = {
        "count": len(ordered),
        "min": ordered[0],
        "max": ordered[-1],
        "mean": statistics.mean(ordered),
    }
    for name, fraction in [("p50", 0.5), ("p95", 0.95), ("p99", 0.99)]:
        result[name] = ordered[math.ceil(len(ordered) * fraction) - 1]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=pathlib.Path)
    args = parser.parse_args()
    directory = args.directory
    with (directory / "frames.csv").open() as source:
        frames = list(csv.DictReader(source))
    with (directory / "frames.csv.profile.csv").open() as source:
        all_profiles = list(csv.DictReader(source))
    profiles = all_profiles[-len(frames) :]
    result = {"frames": stats([float(row["frame_ms"]) for row in frames])}
    # The goal freezes the state frame. Exclude every callback after the first
    # terminal frame, rather than treating repeated frozen frames as movement.
    goal_frames = [
        int(line.split()[-1])
        for line in (directory / "godot.log").read_text().splitlines()
        if line.startswith("EGGSHELL_GOAL ")
    ]
    terminal = goal_frames[0] if goal_frames else None
    moving = []
    for row, profile in zip(frames, profiles, strict=True):
        moving.append(float(row["frame_ms"]))
        if terminal is not None and int(profile["frame"]) >= terminal:
            break
    result["goal_frame"] = terminal
    result["moving_phase_frame_ms"] = stats(moving)
    for field in [
        "sim_ms",
        "view_ms",
        "engine_process_ms",
        "engine_physics_ms",
        "draw_calls",
        "render_objects",
        "video_memory_bytes",
    ]:
        result[field] = stats([float(row[field]) for row in profiles])
    saves = []
    for line in (directory / "godot.log").read_text().splitlines():
        if line.startswith("EGGSHELL_SAVE "):
            saves.append(json.loads(line.removeprefix("EGGSHELL_SAVE ")))
    result["worker_write_ms"] = stats([row["write_ms"] for row in saves])
    result["save_errors"] = [row for row in saves if row["error"]]
    for group, predicate in [
        ("near_autosave", lambda frame: frame % 60 < 3 or frame % 60 > 57),
        ("away_from_autosave", lambda frame: 10 < frame % 60 < 50),
    ]:
        result[group] = {
            field: stats(
                [float(row[field]) for row in profiles if predicate(int(row["frame"]))]
            )
            for field in ["sim_ms", "engine_physics_ms", "engine_process_ms"]
        }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
