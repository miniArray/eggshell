"""The shipped Pantry pack is reproducible offline from its reviewed Nano Banana sources."""

import hashlib
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("host_load", ROOT / "tools/host_load.py")
HOST_LOAD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOST_LOAD)
PACK = ROOT / "packs/pantry"
# Reviewed source bytes; provenance and prompts are in art/pantry/README.md.
SOURCES = {
    "actors.jpg": "bbd224cc092830690d25286a14210ddc3c26bdaf3d1a9d470e47de49448648fb",
    "cabinet.jpg": "8b8022db4821873e5f546f9eb8ba22111a93ce9725d7e7ae1df86df0b964abe9",
    "chick.jpg": "283e721315b6fc0323fbf661b9d3256c011aa7a30919a59b05e85f63d5e15971",
    "crumb.jpg": "6ca8438e372ad36c1634dcb4fdc4249dde2ec90bad0072ca3e37ec3d975795b1",
    "crust.jpg": "7c3595cf12b8c517bb6853574d04e3bb8e41090e5773ce8c988c3f8d954114f7",
    "props.jpg": "1c2a931d4c7d588e1a8e03ec2c2970f22f09c37393869451e086388f9e235ddd",
    "pulp.jpg": "70a63e139d6f4f2fdc2f5be8f818da5fef2a8898a502a747a903d7d50e93969a",
    "wall.jpg": "be35564f94aafd335fe899294fec94ff44561f7d1d724da890c23d7b5eeed16d",
    "water.jpg": "c79d5bb6ae0b509665e4ebfeff2d7091f1418dd2dc309de1a4f6601ee181a232",
    "wood.jpg": "92d58bb473cad8e96c66c9ecbe7c84734e9cc535ae3143b2f6ddfd3c37fcb64b",
}


def godot(*args):
    return subprocess.run(
        ["godot", "--headless", "--path", str(ROOT), *args],
        text=True,
        capture_output=True,
        timeout=HOST_LOAD.limit(120),
        check=False,
    )


class PantryPackTests(unittest.TestCase):
    def test_reviewed_sources_match_recorded_provenance(self):
        for name, digest in SOURCES.items():
            with self.subTest(name=name):
                data = (ROOT / "art/pantry" / name).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)

    def test_pack_shapes_joins_and_files(self):
        result = godot("--script", "tests/pantry_bread.gd")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("SCRIPT ERROR", result.stderr)
        self.assertIn(" 0 failures", result.stdout)

    def test_pack_build_is_offline_and_byte_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            result = godot(
                "--script", "tools/build_pantry_pack.gd", "--", f"--output={directory}"
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            built = sorted(
                path.relative_to(directory)
                for path in pathlib.Path(directory).rglob("*")
                if path.is_file()
            )
            shipped = sorted(
                path.relative_to(PACK)
                for path in PACK.rglob("*")
                if path.is_file() and path.suffix != ".import"
            )
            self.assertEqual(built, shipped)
            for relative in built:
                with self.subTest(file=str(relative)):
                    self.assertEqual(
                        (pathlib.Path(directory) / relative).read_bytes(),
                        (PACK / relative).read_bytes(),
                    )


if __name__ == "__main__":
    unittest.main()
