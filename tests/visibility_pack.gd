extends RefCounted
## Generated stress art: changing dimensions/origins, oversized slices and child parts.
const InputPack = preload("res://tests/density_pack.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")


static func create(density: int = 2) -> String:
	var path := InputPack.create()
	InputPack.image(path, "wide.png", 200, 40)
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(path.path_join("manifest.json"))
	)
	manifest.density = density
	InputPack.image(path, "tile.png", 64 * density, 32 * density)
	var art := {
		"anchor": "position",
		"animations":
		{
			"Default":
			{
				"fps": 60,
				"frames":
				[
					{"file": "object.png", "origin": [6, 18]},
					{"file": "wide.png", "origin": [390, -70]},
					{"file": "object.png", "origin": [-50, 120]}
				]
			}
		}
	}
	for code: String in [
		"o1", "o3", "o10", "o18", "o24", "e1", "e5", "e5_head", "d28", "d29", "d22", "d1"
	]:
		manifest.objects[code] = art.duplicate(true)
	for code: String in ["p2", "p6", "p11"]:
		var span := art.duplicate(true)
		span.slices = {"left": 120, "right": 120, "top": 60, "bottom": 60}
		manifest.objects[code] = span
	manifest.objects.p6_stem = {"file": "object.png", "origin": [6, 18]}
	manifest.objects.p11_spikes = {"file": "wide.png", "origin": [390, -70]}
	InputPack.write_json(path, "manifest.json", manifest)
	return path


static func world() -> Dictionary:
	var code: Dictionary = JSON.parse_string(Fixtures.code("stride"))
	var map: Dictionary = code.maps.map1
	map.width = 4096
	map.height = 4096
	map.objects.merge(
		{
			"coin": {"A": "o1", "X": 200, "Y": 250},
			"flower": {"A": "o3", "X": 520, "Y": 400},
			"grow": {"A": "o10", "X": 600, "Y": 500},
			"message": {"A": "o18", "X": 700, "Y": 600, "E1": "Visibility"},
			"sized": {"A": "o24", "X": 800, "Y": 700},
			"cloud": {"A": "p2", "X": 1000, "Y": 1000, "E1": 120},
			"stem": {"A": "p6", "X": 1400, "Y": 1400, "E1": 12, "E2": 900, "R": 30},
			"spikes": {"A": "p11", "X": 1600, "Y": 1600, "E1": 8, "E2": 0},
			"decor": {"A": "d28", "X": 2000, "Y": 2500, "E1": 600},
			"turned": {"A": "d1", "X": 2200, "Y": 2500, "R": 30, "M": 1},
			"snow": {"A": "d22", "X": 3000, "Y": 3000, "E1": 400},
			"plant": {"A": "e5", "X": 3200, "Y": 3200}
		}
	)
	code.maps.map2 = map.duplicate(true)
	code.maps.map2.objects.coin.X = 3500
	var result := World.build(JSON.stringify(code), Collision.read())
	assert(result.ok, str(result))
	return result.world
