"""Build the real upload archive locally. Never contact the device."""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("device", ROOT / "tools/device.py")
DEVICE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEVICE)


class DevicePackTests(unittest.TestCase):
    def test_supported_versions_and_density_preserve_upload_path_and_bytes(self):
        for version, density in [(2, 1), (3, 1), (3, 2)]:
            with (
                self.subTest(version=version, density=density),
                tempfile.TemporaryDirectory() as directory,
            ):
                root = pathlib.Path(directory)
                pack = root / "pack"
                pack.mkdir()
                manifest = json.dumps({"version": version, "density": density})
                (pack / "manifest.json").write_text(manifest)
                (pack / "image.png").write_bytes(b"pack data")
                archive = root / "upload/pack.tar.gz"
                DEVICE.create_pack_archive(pack, archive)
                with tarfile.open(archive) as contents:
                    self.assertEqual(
                        contents.extractfile("external-v2/manifest.json").read(),
                        manifest.encode(),
                    )
                    self.assertEqual(
                        contents.extractfile("external-v2/image.png").read(),
                        b"pack data",
                    )

    def test_unsupported_or_invalid_versions_do_not_create_an_archive(self):
        for metadata in [
            None,
            [],
            {},
            {"version": 1},
            {"version": 4},
            {"version": "3"},
            {"version": True},
            {"version": []},
        ]:
            with (
                self.subTest(metadata=metadata),
                tempfile.TemporaryDirectory() as directory,
            ):
                pack = pathlib.Path(directory)
                (pack / "manifest.json").write_text(json.dumps(metadata))
                archive = pack / "pack.tar.gz"
                with self.assertRaises(RuntimeError):
                    DEVICE.create_pack_archive(pack, archive)
                self.assertFalse(archive.exists())

    def test_invalid_json_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = pathlib.Path(directory)
            (pack / "manifest.json").write_text("not json")
            with self.assertRaisesRegex(RuntimeError, "Invalid graphics pack manifest"):
                DEVICE.create_pack_archive(pack, pack / "pack.tar.gz")

    def test_cli_rejects_invalid_pack_before_contacting_transport(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = pathlib.Path(directory)
            (pack / "manifest.json").write_text('{"version": 99}')
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/device.py"), "pack", str(pack)],
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "Device play requires a graphics pack version in: 2, 3", result.stderr
            )
            self.assertNotIn("Traceback", result.stderr)

    def test_missing_manifest_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            pack = pathlib.Path(directory)
            with self.assertRaisesRegex(RuntimeError, "Import the graphics pack first"):
                DEVICE.create_pack_archive(pack, pack / "pack.tar.gz")


if __name__ == "__main__":
    unittest.main()
