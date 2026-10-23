"""Real-process lifecycle checks. All game processes use placeholder graphics."""

import hashlib
import json
import os
import pathlib
import random
import signal
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT = ROOT / "build/godot/bin/godot"
RESULTS = ROOT / "build/host-kill-results.json"


def command(directory, *args):
    return [
        "bash",
        str(ROOT / "tools/play"),
        "--headless",
        "--path",
        str(ROOT),
        "--",
        "--placeholder",
        f"--level-code={ROOT / 'tests/fixtures/endurance.level.json'}",
        f"--save-dir={directory}",
        "--trace",
        f"--replay={ROOT / 'tests/fixtures/endurance.input.json'}",
        *args,
    ]


def snapshot_frame(path):
    data = path.read_bytes()
    if (
        len(data) < 364
        or data[:8] != b"EGGSTATE"
        or struct.unpack_from("<I", data, 8)[0] != 3
    ):
        raise AssertionError("Invalid snapshot header/length")
    count = struct.unpack_from("<I", data, 324)[0]
    enemy_offset = 328 + 48 * count
    if enemy_offset + 36 > len(data):
        raise AssertionError("Invalid spring count/length")
    enemies = struct.unpack_from("<I", data, enemy_offset)[0]
    if len(data) != 364 + 48 * count + 160 * enemies:
        raise AssertionError("Invalid enemy count/length")
    if hashlib.sha256(data[:-32]).digest() != data[-32:]:
        raise AssertionError("Invalid snapshot checksum")
    return struct.unpack_from("<q", data, 44)[0]


def run_to(directory, frame, *args):
    result = subprocess.run(
        command(directory, f"--exit-frame={frame}", *args),
        text=True,
        capture_output=True,
        timeout=15,
        check=False,
    )
    if result.returncode != 0 or "SCRIPT ERROR" in result.stderr:
        raise AssertionError(result.stdout + result.stderr)
    return result


def last_frame(text):
    return max(
        [
            int(line.split()[-1])
            for line in text.splitlines()
            if line.startswith("EGGSHELL_TICK ")
        ],
        default=0,
    )


class GameProcessTests(unittest.TestCase):
    def test_window_close_notification_saves_exact_frame(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                command(directory, "--close-frame=137"),
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                snapshot_frame(pathlib.Path(directory) / "autosave.egg"), 137
            )
            self.assertIn("EGGSHELL_EXIT 137", result.stdout)

    def test_close_does_not_advance_remaining_catchup_ticks(self):
        with tempfile.TemporaryDirectory() as directory:
            args = command(directory, "--close-frame=137")
            separator = args.index("--")
            args[separator:separator] = ["--fixed-fps", "10"]
            result = subprocess.run(
                args, capture_output=True, text=True, timeout=10, check=False
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(
                snapshot_frame(pathlib.Path(directory) / "autosave.egg"), 137
            )

    def test_sigterm_saves_exact_current_frame(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "run.log"
            with output.open("w") as log:
                process = subprocess.Popen(
                    command(directory),
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                try:
                    deadline = time.monotonic() + 10
                    while (
                        last_frame(output.read_text()) < 137
                        and time.monotonic() < deadline
                    ):
                        time.sleep(0.005)
                    process.send_signal(signal.SIGTERM)
                    process.wait(timeout=10)
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
            text = output.read_text()
            self.assertEqual(process.returncode, 0, text)
            self.assertEqual(
                snapshot_frame(pathlib.Path(directory) / "autosave.egg"),
                last_frame(text),
            )
            self.assertIn(f"EGGSHELL_EXIT {last_frame(text)}", text)

    def test_bad_autosaves_start_fresh(self):
        with tempfile.TemporaryDirectory() as seed:
            run_to(seed, 3)
            valid = (pathlib.Path(seed) / "autosave.egg").read_bytes()
        wrong_version = bytearray(valid)
        struct.pack_into("<I", wrong_version, 8, 1)
        legacy = bytearray(valid[:180])
        struct.pack_into("<I", legacy, 8, 1)
        legacy.extend(hashlib.sha256(legacy).digest())
        old_v2 = bytearray(valid[:220])
        struct.pack_into("<I", old_v2, 8, 2)
        springs = struct.unpack_from("<I", valid, 324)[0]
        old_v2.extend(valid[324 : 328 + 48 * springs])
        old_v2.extend(hashlib.sha256(old_v2).digest())
        wrong_level = bytearray(valid)
        wrong_level[12:44] = b"x" * 32
        wrong_level[-32:] = hashlib.sha256(wrong_level[:-32]).digest()
        corrupt = bytearray(valid)
        corrupt[90] ^= 1
        for label, data in [
            ("truncated", valid[:-1]),
            ("version", wrong_version),
            ("old-v1", legacy),
            ("old-v2", old_v2),
            ("identity", wrong_level),
            ("checksum", corrupt),
        ]:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                (pathlib.Path(directory) / "autosave.egg").write_bytes(data)
                result = run_to(directory, 2)
                self.assertIn("EGGSHELL_START 0", result.stdout)
                self.assertIn("Ignoring autosave:", result.stderr)
                if label in ["old-v1", "old-v2"]:
                    self.assertIn("Snapshot format/version", result.stderr)

    def test_resume_disabled_does_not_load_or_write_autosave(self):
        with tempfile.TemporaryDirectory() as directory:
            run_to(directory, 3)
            save = pathlib.Path(directory) / "autosave.egg"
            original = save.read_bytes()
            (pathlib.Path(directory) / "settings.json").write_text(
                json.dumps({"version": 1, "resume_where_i_left_off": False})
            )
            result = run_to(directory, 5)
            self.assertIn("EGGSHELL_START 0", result.stdout)
            self.assertEqual(save.read_bytes(), original)

    def test_twenty_sigkills_lose_at_most_two_seconds(self):
        rng = random.Random(77031)
        runs = []
        for index in range(20):
            with tempfile.TemporaryDirectory() as directory:
                output = pathlib.Path(directory) / "run.log"
                windows = [(1317, 1325), (1640, 1660), (1849, 1865), (2316, 2330)]
                lower, upper = windows[index] if index < len(windows) else (25, 2440)
                target = rng.randrange(lower, upper)
                with output.open("w") as log:
                    process = subprocess.Popen(
                        command(directory),
                        stdout=log,
                        stderr=subprocess.STDOUT,
                        start_new_session=True,
                    )
                    try:
                        deadline = time.monotonic() + 45
                        while (
                            last_frame(output.read_text()) < target
                            and time.monotonic() < deadline
                        ):
                            time.sleep(0.005)
                        engine_pid = next(
                            int(line.split()[-1])
                            for line in output.read_text().splitlines()
                            if line.startswith("EGGSHELL_ENGINE_PID ")
                        )
                        os.kill(engine_pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    finally:
                        if process.poll() is None:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                text = output.read_text()
                killed = last_frame(text)
                save = pathlib.Path(directory) / "autosave.egg"
                saved = snapshot_frame(save) if save.exists() else 0
                lost = killed - saved
                self.assertGreaterEqual(killed, target, text)
                self.assertGreaterEqual(lost, 0)
                self.assertLessEqual(lost, 120)
                result = run_to(directory, saved + 2)
                self.assertIn(f"EGGSHELL_START {saved}", result.stdout)
                runs.append(
                    {
                        "run": index + 1,
                        "killed_frame": killed,
                        "saved_frame": saved,
                        "lost_frames": lost,
                        "lost_play_seconds": lost / 60,
                    }
                )
        RESULTS.parent.mkdir(exist_ok=True)
        RESULTS.write_text(json.dumps(runs, indent=2) + "\n")
        losses = sorted(row["lost_play_seconds"] for row in runs)
        print(
            f"HOST_KILLS count=20 min={losses[0]:.6f} median={(losses[9] + losses[10]) / 2:.6f} max={losses[-1]:.6f} seconds; {RESULTS}"
        )


if __name__ == "__main__":
    unittest.main()
