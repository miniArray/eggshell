#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 nix
"""Focused, real-process checks for diagnostics and benchmark write output."""

import csv
import json
import math
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

import host_load

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = ROOT / "build/godot/bin/godot"


def run_godot(*args, env=None):
    args = list(args)
    if "--" not in args:
        args.append("--")
    return subprocess.run(
        [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT),
            *args,
            "--level-code=" + str(ROOT / "tests/fixtures/stride.level.json"),
        ],
        env=env,
        text=True,
        capture_output=True,
        timeout=host_load.limit(40),
        check=False,
    )


class RuntimeChecks(unittest.TestCase):
    def verify_summary(self, path):
        with path.open() as source:
            samples = [float(row["frame_ms"]) for row in csv.DictReader(source)]
        summary = json.loads(path.with_name(path.name + ".summary.json").read_text())
        self.assertGreater(len(samples), 0)
        self.assertEqual(summary["frames"], len(samples))
        ordered = sorted(samples)
        for field, quantile in [("p50_ms", 0.50), ("p95_ms", 0.95), ("p99_ms", 0.99)]:
            self.assertAlmostEqual(
                summary[field],
                ordered[math.ceil(len(samples) * quantile) - 1],
                places=3,
            )
        self.assertAlmostEqual(
            summary["mean_fps"], 1000 * len(samples) / sum(samples), places=3
        )
        self.assertGreater(summary["peak_rss_kib"], 0)
        self.assertEqual(summary["peak_rss_source"], "/proc/self/status VmHWM")

    def test_cli_log_overrides_environment_and_matches_recorded_intervals(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "frames.csv"
            ignored = pathlib.Path(temporary) / "ignored.csv"
            result = run_godot(
                "--quit-after",
                "30",
                "res://bench/sprites.tscn",
                "--",
                f"--frame-log={path}",
                "--frame-warmup=0",
                env={**os.environ, "EGGSHELL_FRAME_LOG": str(ignored)},
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(ignored.exists())
            self.verify_summary(path)

    def test_environment_enables_logging(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "frames.csv"
            result = run_godot(
                "--quit-after",
                "20",
                "res://bench/sprites.tscn",
                "--",
                "--frame-warmup=0",
                env={**os.environ, "EGGSHELL_FRAME_LOG": str(path)},
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.verify_summary(path)

    def test_disabled_logger_has_no_summary(self):
        result = run_godot(
            "--quit-after",
            "5",
            "res://bench/sprites.tscn",
            env={
                key: value
                for key, value in os.environ.items()
                if key != "EGGSHELL_FRAME_LOG"
            },
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("EGGSHELL_FRAME_SUMMARY", result.stdout)

    def test_empty_sample_set_is_valid(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "frames.csv"
            result = run_godot(
                "--quit-after",
                "5",
                "res://bench/sprites.tscn",
                "--",
                f"--frame-log={path}",
                "--frame-warmup=999",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            summary = json.loads(
                path.with_name(path.name + ".summary.json").read_text()
            )
            self.assertEqual(summary["frames"], 0)
            self.assertEqual(summary["mean_fps"], 0)
            self.assertEqual(summary["p99_ms"], 0)

    def test_unwritable_log_fails_explicitly(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = run_godot(
                "--quit-after",
                "5",
                "res://bench/sprites.tscn",
                "--",
                f"--frame-log={temporary}/missing/frames.csv",
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("Cannot open frame log", result.stderr)

    def test_stall_probe_records_every_callback_and_first_draw(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            path = directory / "frames.csv"
            result = run_godot(
                "--quit-after",
                "30",
                "--",
                "--placeholder",
                "--stall-probe",
                f"--save-dir={directory / 'save'}",
                f"--frame-log={path}",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with pathlib.Path(str(path) + ".stall.csv").open() as source:
                frames = list(csv.DictReader(source))
            self.assertGreater(len(frames), 1)
            self.assertTrue(all(int(row["tick"]) >= 0 for row in frames))
            self.assertTrue(all(float(row["interval_ms"]) >= 0 for row in frames))
            events = [
                json.loads(line)
                for line in pathlib.Path(str(path) + ".events.jsonl")
                .read_text()
                .splitlines()
            ]
            self.assertEqual(events[0]["event"], "probe_ready")
            draws = [
                event for event in events if event["event"] == "first_gameplay_draw"
            ]
            # Headless rendering has no post-draw signal. Do not invent load time.
            self.assertEqual(draws, [])
            self.assertTrue(any(event["event"] == "first_visible" for event in events))

    def test_stall_probe_open_error_is_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            path = directory / "frames.csv"
            pathlib.Path(str(path) + ".stall.csv").mkdir()
            result = run_godot(
                "--quit-after",
                "5",
                "--",
                "--placeholder",
                "--stall-probe",
                f"--save-dir={directory / 'save'}",
                f"--frame-log={path}",
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("Cannot open stall probe logs", result.stderr)

    def test_write_benchmark_writes_exact_bytes_and_percentiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = run_godot(
                "res://bench/write_cost.tscn", "--", f"--write-directory={temporary}"
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            directory = pathlib.Path(temporary)
            self.assertEqual(
                (directory / "gdscript-save.bin").read_bytes(), b"Z" * 4096
            )
            self.assertFalse((directory / "gdscript-save.new").exists())
            with (directory / "gdscript-write.csv").open() as source:
                samples = sorted(
                    float(row["operation_ms"]) for row in csv.DictReader(source)
                )
            summary = json.loads(
                (directory / "gdscript-write.summary.json").read_text()
            )
            self.assertEqual(len(samples), 200)
            self.assertEqual(summary["p50_ms"], samples[99])
            self.assertEqual(summary["p99_ms"], samples[197])
            self.assertIn("NO fsync", summary["operation"])

    def test_write_benchmark_can_use_real_fsync(self):
        with tempfile.TemporaryDirectory() as temporary:
            tool = shutil.which("sync")
            self.assertIsNotNone(tool)
            result = run_godot(
                "res://bench/write_cost.tscn",
                "--",
                f"--write-directory={temporary}",
                f"--write-fsync-tool={tool}",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            summary = json.loads(
                (pathlib.Path(temporary) / "gdscript-fsync.summary.json").read_text()
            )
            self.assertEqual(summary["iterations"], 200)
            self.assertIn("(fsync)", summary["operation"])
            self.assertFalse(summary["directory_fsync"])

    def test_failed_fsync_does_not_claim_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = run_godot(
                "res://bench/write_cost.tscn",
                "--",
                f"--write-directory={temporary}",
                "--write-fsync-tool=/missing-sync",
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("fsync tool failed", result.stderr)
            self.assertFalse(
                (pathlib.Path(temporary) / "gdscript-fsync.summary.json").exists()
            )

    def test_missing_write_directory_is_an_error(self):
        result = run_godot("res://bench/write_cost.tscn")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)


if __name__ == "__main__":
    subprocess.run(
        ["nix", "build", f"{ROOT}#godot", "--out-link", str(ROOT / "build/godot")],
        check=True,
    )
    unittest.main()
