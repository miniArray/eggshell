"""Real game startup: graphics selection never selects or supplies a level."""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUNDLED = "res://packs/pantry"


def empty_pack(path):
    """A real v2 graphics-only pack using the existing loader contract."""
    path.mkdir(parents=True)
    (path / "manifest.json").write_text(
        json.dumps(
            {
                "version": 2,
                "tiles": {},
                "player": {},
                "drawing_facts": "drawing_facts.json",
            }
        )
    )
    (path / "drawing_facts.json").write_text(json.dumps({"tilemaps": {}}))
    # A graphics pack's level files must never be read, even if present.
    (path / "levels").mkdir()
    (path / "levels/course.txt").write_text("not a level")
    return path


class PackSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = (ROOT / "tests/fixtures/stride.level.json").read_text()

    def run_game(self, directory, *args, env_pack="", zip_path="missing", level=True):
        base = pathlib.Path(directory)
        environment = os.environ.copy()
        environment.update(
            HOME=str(base / "home"),
            EGGSHELL_PACK=str(env_pack),
        )
        command = [
            "godot",
            "--headless",
            "--path",
            str(ROOT),
            "--fixed-fps",
            "60",
            "--",
            f"--save-dir={base / 'save'}",
            "--exit-frame=2",
        ]
        if level:
            path = base / "level.txt"
            path.write_text(self.code)
            command.append(f"--level-code={path}")
        result = subprocess.run(
            [*command, *args],
            env=environment,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        return result

    def check_started(self, result, pack):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("SCRIPT ERROR", result.stderr)
        self.assertIn(f"EGGSHELL_PACK {pack}\n", result.stdout)
        self.assertIn("EGGSHELL_EXIT 2", result.stdout)

    def test_plain_run_uses_bundled_pantry_not_a_home_import(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            old = base / "home/.local/share/eggshell/packs/unused"
            old.mkdir(parents=True)
            (old / "manifest.json").write_text('{"version": 999}')
            result = self.run_game(directory, zip_path=base / "no-archive")
            self.check_started(result, BUNDLED)
            self.assertNotIn("Unsupported asset pack", result.stderr)

    def test_pantry_requires_an_explicit_level(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_game(directory, level=False)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Pass --level-code=PATH", result.stderr)

    def test_environment_can_select_an_external_graphics_only_pack(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            pack = empty_pack(base / "external")
            result = self.run_game(directory, env_pack=pack, zip_path=base / "missing")
            self.check_started(result, pack)

    def test_cli_pack_wins_over_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            pack = empty_pack(base / "explicit")
            result = self.run_game(
                directory, f"--pack={pack}", env_pack=base / "not-a-pack"
            )
            self.check_started(result, pack)

    def test_external_pack_never_supplies_the_level(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = empty_pack(pathlib.Path(directory) / "external")
            result = self.run_game(directory, f"--pack={pack}", level=False)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Pass --level-code=PATH", result.stderr)

    def test_pack_level_does_not_hide_a_missing_level_source(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            pack = empty_pack(base / "external")
            (pack / "levels/course.txt").write_text(self.code)
            result = self.run_game(
                directory, f"--pack={pack}", level=False, zip_path=base / "missing"
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("Pass --level-code=PATH", result.stderr)
            self.assertNotIn("EGGSHELL_START", result.stdout)

    def test_missing_selected_pack_uses_placeholders_not_a_home_import(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            result = self.run_game(directory, f"--pack={base / 'missing'}")
            self.check_started(result, "placeholders")

    def test_placeholder_flag_bypasses_pack_loading(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = pathlib.Path(directory) / "bad"
            pack.mkdir()
            (pack / "manifest.json").write_text('{"version": 999}')
            self.check_started(
                self.run_game(directory, "--placeholder", env_pack=pack), "placeholders"
            )

    def test_pack_choice_does_not_change_snapshot_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            frames = []
            for name, args in [("pantry", []), ("diagnostic", ["--placeholder"])]:
                run = base / name
                run.mkdir()
                result = self.run_game(run, *args)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                frames.append((run / "save/autosave.egg").read_bytes())
            self.assertEqual(*frames)

    def test_missing_explicit_level_reports_file_without_using_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = pathlib.Path(directory) / "no-level.txt"
            result = self.run_game(directory, f"--level-code={missing}")
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(f"Level file not found: {missing}", result.stderr)
            self.assertNotIn("EGGSHELL_START", result.stdout)

    def test_device_upload_requires_explicit_paths_without_transport(self):
        for command in ["pack", "level"]:
            with self.subTest(command=command):
                result = subprocess.run(
                    ["python3", str(ROOT / "tools/device.py"), command],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("requires one explicit local path", result.stderr)


if __name__ == "__main__":
    unittest.main()
