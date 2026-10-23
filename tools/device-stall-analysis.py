#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
"""Describe raw frame outliers and adjacent profiles without discarding samples."""

import argparse
import csv
import json
import math
import pathlib
import re
import statistics


def rows(path):
    with path.open() as source:
        return list(csv.DictReader(source))


def analyze(directory):
    frames = rows(directory / "frames.csv")
    profiles = rows(directory / "frames.csv.profile.csv")
    offset = len(profiles) - len(frames)
    ordered = sorted(float(row["frame_ms"]) for row in frames)
    summary = json.loads((directory / "frames.csv.summary.json").read_text())
    result = {
        "directory": str(directory),
        "profile_alignment": "tail-aligned callbacks; interval includes previous callback's work",
        "count": len(frames),
        "max_ms": max(ordered),
        "mean_fps": 1000 / statistics.mean(ordered),
        "peak_rss_kib": summary["peak_rss_kib"],
        "percentiles_ms": {
            name: ordered[math.ceil(len(ordered) * fraction) - 1]
            for name, fraction in [("p50", 0.5), ("p95", 0.95), ("p99", 0.99)]
        },
        "outliers": [],
    }
    for index, row in enumerate(frames):
        if float(row["frame_ms"]) <= 50:
            continue
        profile_index = index + offset
        result["outliers"].append(
            {
                **row,
                "profiles": profiles[max(0, profile_index - 2) : profile_index + 2],
            }
        )
    saves = [
        json.loads(line.removeprefix("EGGSHELL_SAVE "))
        for line in (directory / "godot.log").read_text().splitlines()
        if line.startswith("EGGSHELL_SAVE ")
    ]
    result["save_writes"] = saves
    events_path = directory / "frames.csv.events.jsonl"
    if events_path.exists():
        events = [json.loads(line) for line in events_path.read_text().splitlines()]
        result["visibility_events"] = events
        result["first_gameplay_draw_ms"] = next(
            (
                event["usec"] / 1000
                for event in events
                if event["event"] == "first_gameplay_draw"
            ),
            None,
        )
        details = rows(directory / "frames.csv.stall.csv")
        result["detail_callbacks"] = len(details)
        result["process_memory_static_peak_bytes"] = max(
            int(row["static_bytes"]) for row in details
        )
        result["video_memory_peak_bytes"] = max(
            int(row["video_bytes"]) for row in details
        )
        for outlier in result["outliers"]:
            frame_index = next(
                index
                for index, row in enumerate(frames)
                if row["elapsed_ms"] == outlier["elapsed_ms"]
            )
            detail_index = frame_index + len(details) - len(frames)
            outlier["details"] = details[max(0, detail_index - 1) : detail_index + 1]
    proc_path = directory / "proc.txt"
    if proc_path.exists():
        fields = [
            "VmHWM",
            "VmRSS",
            "RssAnon",
            "RssFile",
            "RssShmem",
            "Pss",
            "Private_Dirty",
        ]
        result["proc_max_kib"] = {
            field: max(
                (
                    int(value)
                    for value in re.findall(
                        rf"^{field}:\s+(\d+)", proc_path.read_text(), re.MULTILINE
                    )
                ),
                default=0,
            )
            for field in fields
        }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", type=pathlib.Path, nargs="+")
    options = parser.parse_args()
    print(json.dumps([analyze(path) for path in options.directories], indent=2))


if __name__ == "__main__":
    main()
