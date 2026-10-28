"""Exercise actual GPU sampling through Godot, including on machines without a desktop."""

import os
import pathlib
import select
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PixelRenderTests(unittest.TestCase):
    def test_art_pixels_have_uniform_integer_screen_widths(self):
        self.render("pixel_render", "PIXEL_RENDER_RESULT:")

    def test_pack_backings_and_background_compositing(self):
        self.render("pack_view_render", "PACK_VIEW_RENDER_RESULT:")

    def render(self, script, marker):
        read_fd, write_fd = os.pipe()
        server = subprocess.Popen(
            [
                "Xvfb",
                "-displayfd",
                str(write_fd),
                "-screen",
                "0",
                "832x448x24",
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
                    f"tests/{script}.gd",
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
            self.assertIn(marker, output)
            self.assertIn("0 failures", output)
        finally:
            os.close(read_fd)
            server.terminate()
            server.wait(timeout=10)


if __name__ == "__main__":
    unittest.main()
