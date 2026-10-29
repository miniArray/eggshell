"""Graphics coverage tool: real engine runner on a small invented pack and levels."""

import importlib.util
import json
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/pack_coverage.py"
_spec = importlib.util.spec_from_file_location("pack_coverage", TOOL)
coverage = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(coverage)


def png(path, width, height, rgba=(200, 120, 40, 255)):
    """A real solid-colour RGBA PNG, without image libraries."""
    path.parent.mkdir(parents=True, exist_ok=True)
    row = b"\x00" + bytes(rgba) * width
    raw = zlib.compress(row * height)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", raw)
        + chunk(b"IEND", b"")
    )


def tiny_pack(path):
    """garden32 tiles (2x2 tiles only), coin art, one pose, background 1, gradient sky1."""
    png(path / "tiles/garden32.png", 64, 64)
    png(path / "objects/coin.png", 16, 16)
    png(path / "player/idle.png", 24, 56)
    png(path / "background/hills.png", 64, 32)
    slots = [{"layer": "TilesL1", "layer_index": 6, "z_order": 0}]
    (path / "drawing_facts.json").write_text(
        json.dumps({"tilemaps": {"garden32": {"instances": slots}}})
    )
    (path / "manifest.json").write_text(
        json.dumps(
            {
                "version": 3,
                "drawing_facts": "drawing_facts.json",
                "tiles": {"garden32": "tiles/garden32.png"},
                "player": {
                    "Idle0": {
                        "fps": 0,
                        "loop": True,
                        "frames": [{"file": "player/idle.png", "origin": [12, 56]}],
                    }
                },
                "objects": {"o1": {"file": "objects/coin.png", "origin": [8, 8]}},
                "backgrounds": {"1": {"layers": [{"file": "background/hills.png"}]}},
                "gradients": {"sky1": {"strips": [{"height": 8, "color": [1, 2, 3]}]}},
            }
        )
    )
    return path


def grid(width, height, data):
    return json.dumps(
        {"c2tilemap": True, "width": width, "height": height, "data": data}
    )


def level(path, name, objects, extra):
    world = {"width": 512, "height": 448, "bgcolor": "10,20,30", "objects": objects}
    world.update(extra)
    path.write_text(
        json.dumps(
            {
                "version": "s3.8.0",
                "name": name,
                "author": "Eggshell",
                "desc": "",
                "startpoint": {"map": 1, "X": 64, "Y": 300},
                "maps": {"map1": world},
            }
        )
    )
    return path


def dry_level(path):
    # Cell 10 is past the 2x2 garden32 image; castle32 has no pack art.
    return level(
        path,
        "Dry",
        {
            "coin": {"A": "o1", "X": 100, "Y": 300},
            "red": {"A": "o2", "X": 120, "Y": 300},
            "walker": {"A": "e1", "X": 200, "Y": 300},
            "bubble": {"A": "e16", "X": 260, "Y": 300},
            "melon": {"A": "o25", "X": 300, "Y": 300, "F": 3},
            "unknown": {"A": "e999", "X": 340, "Y": 300},
            "goal": {"A": "o5", "X": 480, "Y": 300},
        },
        {
            "bg1": "1",
            "bg2": "2",
            "gradient": "sky1_0_1",
            "layer1": {
                "garden32": grid(16, 14, "208x-1,0,1,10,13x-1"),
                "castle32": grid(16, 14, "209x-1,15x0"),
            },
        },
    )


def wet_level(path):
    return level(
        path,
        "Wet",
        {"coin": {"A": "o1", "X": 100, "Y": 300}},
        {
            "bg1": "1",
            "bg2": "1",
            "bg3": "1",
            "gradient": "8,40,50,60_0_1",
            "layer1": {"water3": grid(16, 14, "200x-1,24x0")},
        },
    )


def statuses(level_facts, kind):
    return {
        (slot["id"], slot["status"]): slot
        for slot in level_facts["slots"]
        if slot["kind"] == kind
    }


@unittest.skipUnless(
    os.environ.get("EGGSHELL_ENGINE") or shutil.which("godot"), "needs Godot"
)
class EngineCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        base = pathlib.Path(cls.directory.name)
        cls.pack = tiny_pack(base / "pack")
        cls.dry = dry_level(base / "dry.txt")
        cls.wet = wet_level(base / "wet.txt")
        cls.json = base / "out/report.json"
        cls.markdown = base / "out/report.md"
        cls.result = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "--pack",
                str(cls.pack),
                "--json",
                str(cls.json),
                "--markdown",
                str(cls.markdown),
                str(cls.dry),
                "--test-course",
                str(cls.wet),
            ],
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
        )
        cls.report = json.loads(cls.json.read_text()) if cls.json.exists() else {}

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def level(self, name):
        return next(lv for lv in self.report["facts"]["levels"] if lv["name"] == name)

    def test_tool_succeeds_and_writes_both_reports(self):
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        text = self.markdown.read_text()
        self.assertIn("# Graphics coverage: pack", text)
        self.assertIn("## Top", text)
        self.assertIn("### Wet (test course, not counted)", text)

    def test_tilesets_follow_the_loaded_pack_images(self):
        tiles = statuses(self.level("Dry"), "tileset")
        self.assertEqual(tiles[("garden32", "pack")]["instances"], 3)
        self.assertEqual(
            tiles[("garden32", "pack")]["details"],
            {"cells past the pack image, not drawn": 1},
        )
        self.assertEqual(tiles[("castle32", "fallback")]["instances"], 15)

    def test_objects_split_into_pack_fallback_and_engine_missing(self):
        objects = statuses(self.level("Dry"), "object")
        self.assertIn(("o1", "pack"), objects)
        self.assertIn(("o2", "fallback"), objects)
        self.assertIn(("e1", "fallback"), objects)
        self.assertIn(("o5", "fallback"), objects)
        # The bubble and the fire melon are built now; without pack art they are squares.
        self.assertEqual(
            objects[("e16", "fallback")]["details"], {"diagnostic square": 1}
        )
        self.assertEqual(
            objects[("o25", "fallback")]["details"], {"diagnostic square": 1}
        )
        self.assertEqual(
            objects[("e999", "engine-missing")]["details"],
            {"unregistered code; not drawn": 1},
        )
        # Actor walkers never show a separate head, so no head slot is listed.
        self.assertNotIn(("e1_head", "fallback"), objects)

    def test_backgrounds_and_gradients_resolve_through_the_view(self):
        dry = self.level("Dry")
        backgrounds = statuses(dry, "background")
        self.assertIn(("1", "pack"), backgrounds)
        self.assertIn(("2", "fallback"), backgrounds)
        # A missing slot reads as background 0, which this pack lacks.
        self.assertIn(("0", "fallback"), backgrounds)
        self.assertIn(("sky1", "pack"), statuses(dry, "gradient"))
        wet = self.level("Wet")
        self.assertEqual(statuses(wet, "background")[("1", "pack")]["instances"], 3)
        self.assertIn(("custom", "level"), statuses(wet, "gradient"))

    def test_player_poses_come_from_the_selector_and_water_adds_swimming(self):
        dry = statuses(self.level("Dry"), "player")
        wet = statuses(self.level("Wet"), "player")
        self.assertIn(("Idle0", "pack"), dry)
        self.assertEqual(
            dry[("Walk0", "fallback")]["details"], {"pack default pose Idle0": 1}
        )
        self.assertNotIn(("Swim0", "fallback"), dry)
        self.assertIn(("Swim0", "fallback"), wet)

    def test_summary_counts_only_counted_levels(self):
        summary = self.report["summary"]
        self.assertEqual(summary["counted_levels"], [str(self.dry.resolve())])
        tiles = summary["totals"]["tileset"]
        self.assertEqual(tiles["pack"]["slots"], 1)
        self.assertEqual(tiles["fallback"]["slots"], 1)
        missing = {(e["kind"], e["id"]) for e in summary["missing"]}
        self.assertNotIn(("tileset", "water3"), missing)
        engine = {e["id"] for e in summary["engine_missing"]}
        self.assertEqual(engine, {"e999"})

    def test_pack_wide_hud_and_runtime_slots(self):
        hud = {s["id"]: s["status"] for s in self.report["facts"]["hud"]}
        self.assertEqual(
            hud["coins"], "pack"
        )  # The HUD falls back to the o1 object art.
        self.assertEqual(hud["companion"], "fallback")
        scenery = {s["id"]: s["status"] for s in self.report["facts"]["scenery"]}
        self.assertEqual(scenery, {"room wall": "fallback", "supports": "fallback"})
        runtime = {s["id"] for s in self.report["facts"]["runtime"]}
        self.assertIn("enemy_pellet", runtime)
        self.assertTrue(all(not code[1:].isdigit() for code in runtime))


@unittest.skipUnless(
    os.environ.get("EGGSHELL_ENGINE") or shutil.which("godot"), "needs Godot"
)
class EngineErrorTests(unittest.TestCase):
    def test_an_unloadable_level_is_reported_and_fails_the_run(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory)
            pack = tiny_pack(base / "pack")
            bad = level(
                base / "bad.txt",
                "Bad",
                {},
                {"layer1": {"noSuchTiles": grid(1, 1, "0")}},
            )
            out = base / "report.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL),
                    "--pack",
                    str(pack),
                    "--json",
                    str(out),
                    str(bad),
                ],
                capture_output=True,
                text=True,
                timeout=300,
                check=False,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("Unsupported tilemap: noSuchTiles", result.stderr)
            levels = json.loads(out.read_text())["facts"]["levels"]
            self.assertIn("error", levels[0])


class SummaryTests(unittest.TestCase):
    """The ranking and totals are pure functions of the runner's facts."""

    def facts(self):
        def slot(kind, slot_id, status, instances):
            return {
                "kind": kind,
                "id": slot_id,
                "status": status,
                "instances": instances,
                "details": {},
            }

        return {
            "engine_poses": {"dry": ["Idle0"], "water": ["Swim0"], "rarest_hits": 1},
            "hud": [],
            "scenery": [],
            "runtime": [],
            "levels": [
                {
                    "file": "a",
                    "name": "A",
                    "features": {"water": True, "lava": False, "maps": 1},
                    "slots": [
                        slot("object", "o1", "fallback", 5),
                        slot("object", "o2", "fallback", 50),
                        slot("tileset", "t", "pack", 100),
                        slot("object", "e16", "engine-missing", 2),
                    ],
                },
                {
                    "file": "b",
                    "name": "B",
                    "features": {"water": False, "lava": True, "maps": 2},
                    "slots": [slot("object", "o1", "fallback", 1)],
                },
                {
                    "file": "c",
                    "name": "C",
                    "features": {"water": False, "lava": False, "maps": 1},
                    "slots": [slot("object", "o2", "fallback", 999)],
                },
            ],
        }

    def test_rank_by_levels_then_instances_and_skip_uncounted(self):
        summary = coverage.summarize(
            self.facts(), ["a", "b"], {"o1": "Coin"}, ["Idle0", "Spin"]
        )
        ranked = [(e["id"], e["levels"], e["instances"]) for e in summary["missing"]]
        self.assertEqual(ranked, [("o1", 2, 6), ("o2", 1, 50)])
        self.assertEqual(summary["missing"][0]["label"], "Coin")
        self.assertEqual([e["id"] for e in summary["engine_missing"]], ["e16"])
        objects = summary["totals"]["object"]
        self.assertEqual(objects["fallback"]["slots"], 2)
        self.assertEqual(objects["fallback"]["uses"], 3)
        self.assertEqual(summary["totals"]["tileset"]["pack"]["instances"], 100)
        mechanics = summary["mechanics"]
        self.assertEqual(mechanics["reference_poses_never_requested"], ["Spin"])
        self.assertEqual(mechanics["levels_with_several_maps"], ["B"])

    def test_coverage_ignores_engine_missing(self):
        summary = coverage.summarize(self.facts(), ["a"])
        self.assertEqual(coverage.coverage(summary["totals"]["object"], "slots"), "0%")
        self.assertEqual(
            coverage.coverage(summary["totals"]["tileset"], "slots"), "100%"
        )
        self.assertEqual(
            coverage.coverage(summary["totals"]["gradient"], "slots"), "n/a"
        )


if __name__ == "__main__":
    unittest.main()
