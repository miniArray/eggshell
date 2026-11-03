extends SceneTree
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var code := FileAccess.get_file_as_string(args[0])
	var decoded: Variant = JSON.parse_string(code)
	if decoded is String:
		code = decoded
	var built := World.build(code, Collision.read())
	if not built.ok:
		push_error(str(built))
		quit(1)
		return
	var world: Dictionary = built.world
	var result := {
		"identity": world.identity,
		"initial_map": world.initial_map,
		"spawn_x": world.spawn_x,
		"spawn_y": world.spawn_y,
		"flowers_target": world.flowers_target,
		"redcoins_target": world.redcoins_target,
		"maps": []
	}
	var probe_count := 0
	for map: Dictionary in world.maps.values():
		var layers := []
		for layer: Dictionary in map.layers:
			var shapes := []
			for cell: int in layer.polygons:
				shapes.append([cell, Array(layer.polygons[cell])])
			layers.append(
				{
					"source_layer": layer.layer,
					"tilemap": layer.name,
					"tile_size_pixels": layer.size,
					"slot": layer.slot,
					"solid": layer.solid,
					"water": layer.water,
					"width": layer.width,
					"height": layer.height,
					"cells": Array(layer.cells),
					"shapes": shapes
				}
			)
		var placements := []
		for source: Dictionary in map.entities:
			if source.has("placeholder"):
				push_error("Unbuilt reference placement")
				quit(1)
				return
			placements.append(
				{
					"id": source.id,
					"code": source.code,
					"x": source.x,
					"y": source.y,
					"variant": source.variant,
					"mirror": source.mirror,
					"rotation": source.rotation,
					"layer": source.layer
				}
			)
		var bridges := []
		for bridge: Dictionary in map.bridges:
			bridges.append({"left": bridge.left, "right": bridge.right, "top": bridge.top})
		var probes := []
		for x in range(-32 * 3600, map.width + 32 * 3600, 31 * 3600):
			for y in range(-32 * 3600, map.height + 32 * 3600, 29 * 3600):
				var box := [x, y, x + 24 * 3600, y + 56 * 3600]
				probes.append(
					[
						box,
						World.tiles_overlap_box(map, box[0], box[1], box[2], box[3]),
						World.border_overlaps(map, box[0], box[1], box[2], box[3])
					]
				)
				probe_count += 1
		result.maps.append(
			{
				"name": map.map_name,
				"width_pixels": map.width / 3600,
				"height_pixels": map.height / 3600,
				"layers": layers,
				"placements": placements,
				"bridges": bridges,
				"probes": probes
			}
		)
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(result, "", false, true))
	print("WORLD_ORACLE_DONE maps=%d probes=%d" % [result.maps.size(), probe_count])
	quit(0)
