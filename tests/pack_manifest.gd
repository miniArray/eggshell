extends SceneTree
## Synthetic metadata only. No level, scene, image or audio is loaded.
const Pack = preload("res://src/level/asset_pack.gd")
const Frames = preload("res://src/view/pack_frames.gd")
var _directory: String
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_directory = OS.get_environment("TMPDIR").path_join("pack-metadata-%d" % OS.get_process_id())
	if not _directory.is_absolute_path():
		_directory = "/tmp/pack-metadata-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_directory)
	write_json("drawing_facts.json", {"tilemaps": {}})
	for version: int in [2, 3]:
		var manifest := base(version)
		write_json("manifest.json", manifest)
		check(not Pack.read(_directory).is_empty(), "version %d accepted" % version)
		check(Pack.read(_directory).density == 1, "Missing density defaults to 1")
		for density: Variant in [1, 2, 3, 4, 0, -1, 5, 1.5, "2", true, null]:
			manifest["density"] = density
			write_json("manifest.json", manifest)
			var expected: int = (
				int(density) if density in [1, 2, 3, 4] and not density is bool else 1
			)
			check(Pack.read(_directory).density == expected, "Density boundary %s" % str(density))
	var manifest := base(3)
	manifest["objects"] = {
		"o1": {"file": "objects/one.png", "origin": [4, 8]},
		"e1": {"animations": {"move": animation()}, "default_animation": "move"},
		"bad": {"animations": {"move": {"frames": "not an array"}}},
		"escape": {"file": "../outside.png", "origin": [0, 0]},
		"scalar": false,
	}
	manifest["player"] = {"Idle0": animation(), "broken": {"frames": [false]}}
	manifest["backgrounds"] = {"7": {"layers": []}}
	manifest["gradients"] = {"sky": {"strips": []}}
	manifest["hud"] = {"meter": {"file": "hud/meter.png"}}
	manifest["fonts"] = {}
	manifest["audio"] = {"music": {"1": "audio/one.ogg"}, "effects": {}}
	write_json("manifest.json", manifest)
	var loaded := Pack.read(_directory)
	check(
		loaded.objects.size() == 2 and loaded.objects.has("o1") and loaded.objects.has("e1"),
		"invalid optional visuals removed"
	)
	check(loaded.player.keys() == ["Idle0"], "invalid player animation removed")
	check(loaded.backgrounds.has("7") and loaded.audio.music.has("1"), "optional maps retained")
	manifest = base(2)
	manifest.player = {
		"Idle0": {"speed": 12, "frames": [{"file": "player/idle.png", "origin": [3, 6]}]}
	}
	write_json("manifest.json", manifest)
	check(Pack.read(_directory).player.has("Idle0"), "legacy speed accepted")
	manifest = base(3)
	for section: String in ["objects", "backgrounds", "gradients", "hud", "fonts", "audio"]:
		manifest[section] = ["wrong shape"]
	write_json("manifest.json", manifest)
	loaded = Pack.read(_directory)
	for section: String in ["objects", "backgrounds", "gradients", "hud", "fonts", "audio"]:
		check(loaded[section] == {}, "bad optional section falls back: " + section)
	manifest = base(3)
	manifest.tiles = {"broken": "tiles/broken.png"}
	manifest.background = {"wall": false}
	write_json("drawing_facts.json", {"tilemaps": {"broken": {"instances": [false]}}})
	write_json("manifest.json", manifest)
	loaded = Pack.read(_directory)
	check(
		loaded.tiles.is_empty() and loaded.drawing.tilemaps.is_empty(),
		"bad draw slots removed before view access"
	)
	check(not loaded.has("background"), "bad legacy scenery falls back")
	write_json("drawing_facts.json", {"tilemaps": {}})
	manifest = base(99)
	write_json("manifest.json", manifest)
	check(Pack.read(_directory).is_empty(), "unknown version rejected")
	manifest = base(3)
	manifest.tiles = []
	write_json("manifest.json", manifest)
	check(Pack.read(_directory).is_empty(), "invalid required shape rejected")
	check(Pack.read(_directory.path_join("missing")).is_empty(), "missing pack uses placeholders")
	for file: String in [
		"/absolute.png", "../up.png", "dir/../up.png", "res://foreign.png", "bad\\path.png"
	]:
		check(not Pack.safe_file(file), "unsafe file rejected: " + file)
	check(Pack.safe_file("objects/frame.png"), "relative file accepted")
	manifest = base(3)
	manifest["terrain"] = {
		"castle32":
		{
			"surface": {"file": "terrain/moss.png", "edge": 4},
			"underside": {"file": "terrain/drip.png"},
			"side": {"file": "../outside.png"},
			"corner": {"file": "terrain/corner.png"},
		},
		"garden32": {"surface": {"file": "terrain/moss.png", "edge": -1}},
		"water3": {"surface": {"file": "terrain/water.png", "edge": 1.5}},
		"lava": false,
	}
	write_json("manifest.json", manifest)
	loaded = Pack.read(_directory)
	check(loaded.terrain.keys() == ["castle32"], "Terrain entries without a valid strip removed")
	check(
		loaded.terrain.castle32.keys() == ["surface", "underside"],
		"Unsafe files and unknown strip kinds removed"
	)
	manifest.terrain = ["wrong shape"]
	write_json("manifest.json", manifest)
	check(Pack.read(_directory).terrain == {}, "Bad terrain section falls back")
	manifest.erase("terrain")
	write_json("manifest.json", manifest)
	check(not Pack.read(_directory).has("terrain"), "Packs without terrain gain no section")
	check(
		not Pack.visual_ok({"file": "frame.png", "animations": [false]}),
		"mixed invalid animation shape rejected"
	)
	check(
		not Pack.animation_ok({"fps": -1, "frames": [{"file": "frame.png"}]}),
		"negative fps rejected"
	)
	check(
		not Pack.animation_ok({"fps": 3, "frames": [{"file": "frame.png", "duration": 0}]}),
		"zero duration rejected"
	)
	check(
		not Pack.visual_ok({"file": "frame.png", "origin": ["bad", 0]}), "invalid origin rejected"
	)
	var art := {
		"default_animation": "move",
		"states": {},
		"animations":
		{
			"move":
			{
				"frames": [{"id": 0, "end": 1.0}, {"id": 1, "end": 3.0}],
				"fps": 60.0,
				"duration": 3.0,
				"loop": true
			}
		}
	}
	check(Frames.sample(art, 1).id == 1, "frame durations select the next frame")
	check(Frames.sample(art, 3).id == 0, "looping animation wraps")
	art.animations.move.loop = false
	check(Frames.sample(art, 300).id == 1, "non-looping animation holds its last frame")
	art.animations.move.fps = 0
	check(Frames.sample(art, 300, "", 1).id == 1, "zero fps selects a fixed variant")
	DirAccess.remove_absolute(_directory.path_join("manifest.json"))
	DirAccess.remove_absolute(_directory.path_join("drawing_facts.json"))
	DirAccess.remove_absolute(_directory)
	print("Pack metadata: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


static func base(version: int) -> Dictionary:
	return {"version": version, "tiles": {}, "player": {}, "drawing_facts": "drawing_facts.json"}


static func animation() -> Dictionary:
	return {
		"fps": 8, "loop": true, "origin": [2, 4], "frames": [{"file": "frame.png", "duration": 1}]
	}


func write_json(file: String, value: Dictionary) -> void:
	var output := FileAccess.open(_directory.path_join(file), FileAccess.WRITE)
	output.store_string(JSON.stringify(value))
	output.close()


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
