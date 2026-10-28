extends RefCounted
## Generated pack inputs shared by load and GPU checks. No art is stored in the repo.
const Fixtures = preload("res://tests/fixtures.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")


static func create() -> String:
	var path := "/tmp/eggshell-density-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(path)
	image(path, "tile.png", 128, 64)
	image(path, "player.png", 48, 112)
	image(path, "object.png", 16, 20)
	image(path, "shelf.png", 24, 12)
	write_json(
		path,
		"manifest.json",
		{
			"version": 3,
			"density": 2,
			"tiles": {"castle32": "tile.png"},
			"drawing_facts": "drawing_facts.json",
			"player":
			{
				"Idle0":
				{
					"fps": 60,
					"origin": [24, 112],
					"frames": [{"file": "player.png"}, {"file": "player.png", "origin": [25, 111]}]
				}
			},
			"objects":
			{
				"o1": {"file": "object.png", "origin": [6, 18], "anchor": "position"},
				"e1": {"file": "object.png", "origin": [6, 18], "anchor": "position"},
				"o5": {"file": "object.png", "origin": [6, 18]},
				"p1": {"file": "object.png", "origin": [6, 18]},
				"recovery":
				{
					"default_animation": "bubble",
					"animations":
					{"bubble": {"fps": 0, "origin": [6, 18], "frames": [{"file": "object.png"}]}}
				}
			},
			"hud": {"countdown": {"file": "object.png"}},
			"fonts":
			{
				"hud":
				{"file": "object.png", "cell_width": 8, "cell_height": 10, "characters": "0123"}
			},
			"background": {"wall": "object.png", "counter": "object.png", "cabinet": "object.png"},
			"supports": {"shelf": "shelf.png", "bracket": "object.png"},
			"gradients":
			{
				"sky":
				{
					"strips":
					[{"height": 40, "color": [0, 0, 0]}, {"height": 40, "color": [255, 255, 255]}]
				}
			},
			"backgrounds":
			{
				"7":
				{
					"layers":
					[
						{
							"animation":
							{"fps": 0, "origin": [6, 18], "frames": [{"file": "object.png"}]},
							"anchor": [40, 60],
							"reference": [80, 100],
							"repeat_size": [32, 40],
							"scroll": [0.5, 0.5],
							"repeat_x": true
						}
					]
				}
			}
		}
	)
	write_json(
		path,
		"drawing_facts.json",
		{
			"tilemaps":
			{"castle32": {"instances": [{"layer": "castle32L1", "layer_index": 0, "z_order": 0}]}}
		}
	)
	return path


static func world() -> Dictionary:
	var code: Dictionary = JSON.parse_string(Fixtures.code("stride"))
	code.maps.map1.width = 4096
	code.maps.map1.height = 4096
	code.maps.map1.bg1 = "7"
	code.maps.map1.gradient = "sky_10_2"
	code.maps.map1.objects["coin"] = {"A": "o1", "X": 200, "Y": 250}
	code.maps.map1.objects["bridge"] = {"A": "p1", "X": 300, "Y": 300, "E1": 64}
	return World.build(JSON.stringify(code), Collision.read()).world


static func image(path: String, file: String, width: int, height: int) -> void:
	var pixels := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			pixels.set_pixel(x, y, Color(x % 2, y % 2, 1, 1))
	pixels.save_png(path.path_join(file))


static func write_json(path: String, file: String, data: Dictionary) -> void:
	var output := FileAccess.open(path.path_join(file), FileAccess.WRITE)
	output.store_string(JSON.stringify(data))
	output.close()


static func remove(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
