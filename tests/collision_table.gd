extends SceneTree
## Collision table shape and terrain load rules. Invented levels only; no scenes or assets.

const Table = preload("res://src/level/collision_table.gd")
const World = preload("res://src/sim/world.gd")
const FIELDS := [
	"collision_disabled",
	"collision_full",
	"collision_polygons",
	"max_tile_id",
	"solid_family",
	"tile_size",
	"water_family"
]
var checks := 0
var failures := 0


func _initialize() -> void:
	table_checks()
	load_checks()
	print("COLLISION_TABLE_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func table_checks() -> void:
	var table := Table.read()
	check(table.version == 2, "Table keeps format version 2")
	check(table.tilemaps.size() == 137, "Table covers every source tileset")
	var names: Array = table.tilemaps.keys()
	var sorted := names.duplicate()
	sorted.sort()
	check(names == sorted, "Tilesets are sorted by name")
	for name: String in names:
		var tile: Dictionary = table.tilemaps[name]
		var keys: Array = tile.keys()
		keys.erase("instances")
		keys.sort()
		check(keys == FIELDS, "Seven-field record: " + name)
		check(tile.tile_size[0] > 0 and tile.tile_size[1] > 0, "Positive tile size: " + name)
		var seen := {}
		var ids: Array = tile.collision_full + tile.collision_disabled
		for key: String in tile.collision_polygons:
			ids.append(key.to_int())
			var points: Array = tile.collision_polygons[key]
			check(points.size() >= 6 and points.size() % 2 == 0, "Polygon pairs: " + name)
		for id: Variant in ids:
			check(not seen.has(int(id)), "Tile listed once: %s %d" % [name, id])
			seen[int(id)] = true
		check(seen.size() == int(tile.max_tile_id) + 1, "Every tile id classified: " + name)
		check(tile.instances.size() == 2, "Diagnostic slots for both layers: " + name)


func load_checks() -> void:
	var square := facts([32, 32], [{"layer": "L1", "layer_index": 1, "z_order": 0}])
	var built := World.build(level({"layer2": {"front": grid()}}), {"tilemaps": {"front": square}})
	check(built.ok, "Missing draw slot falls back instead of refusing")
	if built.ok:
		var layer: Dictionary = built.world.maps[1].layers[0]
		check(layer.slot == [0, 0], "Fallback slot draws behind regular terrain")
		check(layer.solid, "Fallback slot keeps solid membership")
	built = World.build(level({"layer1": {"front": grid()}}), {"tilemaps": {"front": square}})
	check(built.ok and built.world.maps[1].layers[0].slot == [1, 0], "Matching slot is kept")
	var tall := facts([32, 448], [])
	built = World.build(level({"layer1": {"tall": grid()}}), {"tilemaps": {"tall": tall}})
	check(
		not built.ok and built.error == "map1: Unsupported tile shape: tall", "Non-square refused"
	)
	built = World.build(level({"layer1": {"absent": grid()}}), {"tilemaps": {}})
	check(not built.ok and built.error == "map1: Unsupported tilemap: absent", "Absent refused")


static func facts(size: Array, instances: Array) -> Dictionary:
	return {
		"tile_size": size,
		"max_tile_id": 0,
		"solid_family": true,
		"water_family": false,
		"collision_full": [0],
		"collision_disabled": [],
		"collision_polygons": {},
		"instances": instances
	}


static func grid() -> String:
	return JSON.stringify({"c2tilemap": true, "width": 2, "height": 1, "data": "2x0"})


static func level(layers: Dictionary) -> String:
	var map := {"width": 64, "height": 32, "objects": {}}
	map.merge(layers)
	return JSON.stringify(
		{
			"version": "1",
			"name": "Invented terrain",
			"desc": "",
			"author": "",
			"startpoint": {"map": 1, "X": 16, "Y": 0},
			"maps": {"map1": map}
		}
	)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
