"""Terrain strips through actual GPU sampling, including on machines without a desktop."""

import os
import pathlib
import select
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class TerrainRenderTests(unittest.TestCase):
    def test_strips_land_on_open_edges_only(self):
        read_fd, write_fd = os.pipe()
        server = subprocess.Popen(
            [
                "Xvfb",
                "-displayfd",
                str(write_fd),
                "-screen",
                "0",
                "1920x1080x24",
                "-nolisten",
                "tcp",
            ],
            pass_fds=(write_fd,),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.close(write_fd)
        try:
            self.assertTrue(
                select.select([read_fd], [], [], 20)[0], "Xvfb did not start"
            )
            display = os.read(read_fd, 128).decode().strip()
            self.assertTrue(display, "Xvfb exited before opening a display")
            environment = {
                **os.environ,
                "DISPLAY": f":{display}",
                "LIBGL_ALWAYS_SOFTWARE": "1",
            }
            result = subprocess.run(
                [
                    "godot",
                    "--path",
                    str(ROOT),
                    "--audio-driver",
                    "Dummy",
                    "--rendering-method",
                    "gl_compatibility",
                    "--script",
                    "tests/terrain_render.gd",
                ],
                env=environment,
                capture_output=True,
                text=True,
                timeout=180,
                check=False,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn("SCRIPT ERROR", output)
            self.assertIn("TERRAIN_RENDER_RESULT:", output)
            self.assertIn("0 failures", output)
        finally:
            os.close(read_fd)
            server.terminate()
            server.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
