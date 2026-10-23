#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
"""Sanitize strace into save-I/O and shader-cache timestamps, never asset paths."""

import argparse
import json
import pathlib
import re


def calls(path):
    pending = {}
    for line in path.read_text().splitlines():
        match = re.match(r"^(\d+)\s+(\d+\.\d+)\s+(.*)$", line)
        if not match:
            continue
        thread, timestamp, call = match.groups()
        timestamp = float(timestamp)
        if call.endswith("<unfinished ...>"):
            pending[thread] = (timestamp, call.removesuffix("<unfinished ...>"))
            continue
        if call.startswith("<... "):
            if thread not in pending:
                continue
            timestamp, prefix = pending.pop(thread)
            call = prefix + call.split("resumed>", 1)[-1]
        duration = re.search(r"<([\d.]+)>$", call)
        elapsed = float(duration[1]) if duration else 0
        yield int(thread), timestamp, timestamp + elapsed, call


def analyze(directory):
    events = [
        json.loads(line)
        for line in (directory / "frames.csv.events.jsonl").read_text().splitlines()
    ]
    ready = next(event for event in events if event["event"] == "probe_ready")
    epoch = ready["unix"] - ready["usec"] / 1_000_000
    writes = [
        json.loads(line.removeprefix("EGGSHELL_SAVE "))
        for line in (directory / "godot.log").read_text().splitlines()
        if line.startswith("EGGSHELL_SAVE ")
    ]
    result = {
        "label": directory.name,
        "clock": "Godot monotonic engine milliseconds, calibrated by probe_ready unix/usec",
        "worker_io_windows": [],
        "shader_cache_events": [],
    }
    active = {}
    for thread, began, ended, call in calls(directory / "syscalls.txt"):
        record = {
            "thread": thread,
            "start_ms": round((began - epoch) * 1000, 3),
            "end_ms": round((ended - epoch) * 1000, 3),
        }
        if "autosave.egg.new" in call:
            if call.startswith("openat(") and "O_WRONLY" in call:
                active[thread] = record
            if call.startswith(("rename(", "renameat(", "renameat2(")) and re.search(
                r"= 0 <", call
            ):
                start = active.pop(thread, None)
                if start is not None:
                    result["worker_io_windows"].append(
                        {
                            "thread": thread,
                            "start_ms": start["start_ms"],
                            "end_ms": record["end_ms"],
                            "io_ms": round(record["end_ms"] - start["start_ms"], 3),
                        }
                    )
        if "shader_cache/" in call and call.startswith("openat("):
            # Keep only cache category, operation and outcome, not filenames or buffers.
            category = call.split("shader_cache/", 1)[1].split("/", 1)[0]
            result["shader_cache_events"].append(
                {
                    **record,
                    "category": category,
                    "operation": "write" if "O_WRONLY" in call else "read",
                    "cache_miss": "ENOENT" in call,
                }
            )
    complete = len(result["worker_io_windows"]) == len(writes)
    result["reported_write_count"] = len(writes)
    result["tick_alignment_complete"] = complete
    if complete:
        for window, write in zip(result["worker_io_windows"], writes, strict=True):
            window["tick"] = write["frame"]
            window["worker_reported_ms"] = write["write_ms"]
    draw = next(
        (
            event["usec"] / 1000
            for event in events
            if event["event"] == "first_gameplay_draw"
        ),
        None,
    )
    result["first_gameplay_draw_ms"] = draw
    result["goal_first_visible_ms"] = next(
        (
            event["usec"] / 1000
            for event in events
            if event["event"] == "first_visible" and event["kind"] == "goal"
        ),
        None,
    )
    result["shader_cache_events_after_first_draw"] = (
        [event for event in result["shader_cache_events"] if event["start_ms"] > draw]
        if draw is not None
        else None
    )
    result["worker_boundary_limit"] = (
        "Measured open-for-write entry through successful rename return, not the GDScript worker function's entry/exit. Worker write_ms includes directory checks."
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=pathlib.Path)
    options = parser.parse_args()
    print(json.dumps(analyze(options.directory), indent=2))


if __name__ == "__main__":
    main()
