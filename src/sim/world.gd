class_name SimWorld
extends RefCounted

const Reader = preload("res://src/level/level_code.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Maps = preload("res://src/sim/maps.gd")
const S := preload("res://src/sim/units.gd").SCALE


static func build(code: String, facts: Dictionary) -> Dictionary:
	var parsed := Reader.parse(code)
	if not parsed.ok:
		return parsed
	var source: Dictionary = parsed.level
	var names: Array = source.maps.keys()
	names.sort_custom(
		func(a: String, b: String) -> bool: return a.substr(3).to_int() < b.substr(3).to_int()
	)
	var world := {
		"identity": code.sha256_text(),
		"source": source,
		"maps": {},
		"map_count": names.size(),
		"initial_map": names.find("map%d" % int(source.startpoint.map)) + 1,
		"spawn_x": roundi(source.startpoint.X * S),
		"spawn_y": roundi(source.startpoint.Y * S),
		"spawn_facing": -1 if int(source.startpoint.get("M", 0)) == 1 else 1,
		"player_palette": palette(source.startpoint.get("palette", "")),
		"flowers_target": maxi(0, int(source.flowers)),
		"redcoins_target": maxi(0, int(source.redcoins)),
		"info":
		{
			"name": source.name,
			"author": source.author,
			"desc": source.desc,
			"version": source.version,
			"revision": Reader.revision(source.version)
		}
	}
	for index in names.size():
		var map_name: String = names[index]
		var compiled := _build_map(source.maps[map_name], facts)
		if not compiled.ok:
			return {"ok": false, "error": "%s: %s" % [map_name, compiled.error]}
		compiled.world.map_index = index + 1
		compiled.world.map_name = map_name
		world.maps[index + 1] = compiled.world
	Maps.select_map(world, world.initial_map)
	return {"ok": true, "world": world}


static func _build_map(map: Dictionary, facts: Dictionary) -> Dictionary:
	var world := {
		"map_source": map,
		"width": int(map.width) * S,
		"height": int(map.height) * S,
		"layers": [],
		"goals": [],
		"springs": [],
		"enemies": [],
		"bridges": [],
		"bgcolor": map.get("bgcolor", "132,222,255"),
		"music": music(map.get("music", 0)),
		"darkness": int(clampf(_numeric(map.get("darkness", 0)), 0.0, 100.0)),
		"tint": str(map.get("tint", "0_255,255,255")),
		"cave_shimmer": int(_numeric(map.get("caveShimmer", 0)) == 1),
		"dice_colours": dice_colours(map.get("diceBlockColours", ""))
	}
	var objects := _build_objects(map, world)
	if not objects.ok:
		return objects
	return _load_layers(map, world, facts)


static func _build_objects(map: Dictionary, world: Dictionary) -> Dictionary:
	for object: Dictionary in map.objects.values():
		if object.A in ["e1", "e2", "e3", "e5", "e20"]:
			for field: String in ["F", "M", "R"]:
				var value: Variant = object.get(field, 0)
				if (
					not (value is int or value is float)
					or not is_finite(value)
					or value != floor(value)
					or value < 0
				):
					return {"ok": false, "error": "Invalid enemy field: " + field}
			var variant := int(object.get("F", 0))
			if int(object.get("R", 0)) != 0 or int(object.get("M", 0)) > 2 or variant > 4:
				return {"ok": false, "error": "Unsupported enemy variant, mirror or rotation"}
			if object.A in ["e3", "e5"] and variant != 0:
				return {"ok": false, "error": "Unsupported flower or plant variant"}
			if object.A == "e20" and variant not in [0, 1]:
				return {"ok": false, "error": "Unsupported fish mode"}
			world.enemies.append(
				{
					"code": object.A,
					"x": roundi(object.X * S),
					"y": roundi(object.Y * S),
					"variant": variant,
					"mirror": int(object.get("M", 0))
				}
			)
		if object.A == "o5":
			world.goals.append([roundi(object.X * S), roundi(object.Y * S)])
		elif object.A == "o11":
			var variant := int(object.get("F", 0))
			world.springs.append(
				{
					"x": roundi(object.X * S),
					"y": roundi((object.Y + 16) * S),
					"large": variant % 2,
					"single_use": int(variant >= 2)
				}
			)
		elif object.A == "p1":
			var width := roundi(float(object.E1) * S)
			world.bridges.append(
				{
					"left": roundi(object.X * S) - width / 2,
					"right": roundi(object.X * S) + width / 2,
					"top": roundi((object.Y - 16) * S)
				}
			)
	return {"ok": true}


static func _load_layers(map: Dictionary, world: Dictionary, facts: Dictionary) -> Dictionary:
	for layer_name: String in ["layer2", "layer1", "layer3"]:
		for name: String in map.get(layer_name, {}):
			if not facts.tilemaps.has(name):
				return {"ok": false, "error": "Unsupported tilemap: " + name}
			var tile: Dictionary = facts.tilemaps[name]
			var grid: Dictionary = map[layer_name][name]
			var slot := []
			for instance: Dictionary in tile.instances:
				var source_layer: String = instance.layer
				if (
					(layer_name == "layer1" and source_layer.ends_with("L1"))
					or (layer_name == "layer2" and source_layer.ends_with("L2"))
				):
					slot = [int(instance.layer_index), int(instance.z_order)]
			if layer_name == "layer3":
				# Optional overlay terrain has no physical role.
				slot = [16, 0]
			if slot.is_empty():
				return {"ok": false, "error": "Missing source draw slot: " + name}
			var bounds := {}
			var polygons := {}
			if tile.solid_family or tile.water_family or name in ["lava", "lava_3", "ySSpikes"]:
				for cell: int in grid.cells:
					if cell != -1 and not bounds.has(cell):
						var points := tile_polygon(cell, tile)
						polygons[cell] = points
						bounds[cell] = polygon_bounds(points)
			world.layers.append(
				{
					"name": name,
					"layer": layer_name,
					"slot": slot,
					"size": int(tile.tile_size[0]),
					"width": int(grid.width),
					"height": int(grid.height),
					"cells": grid.cells,
					"bounds": bounds,
					"polygons": polygons,
					"solid": tile.solid_family and layer_name != "layer3",
					"water": tile.water_family and layer_name != "layer3"
				}
			)
	world.layers.sort_custom(_draw_before)
	return {"ok": true, "world": world}


static func music(value: Variant) -> Dictionary:
	if value is Dictionary:
		return {
			"id": str(value.get("src", "")),
			"settings": str(value.get("dat", "0,0")),
			"custom": true
		}
	var id := (
		String.num(float(value)).trim_suffix(".0") if value is float or value is int else str(value)
	)
	return {"id": id, "settings": "0,0", "custom": false}


static func palette(value: Variant) -> Array:
	var colours := []
	if value is String and not value.is_empty():
		for token: String in value.split("_"):
			colours.append(rgb(token))
	return colours


static func rgb(value: String) -> Array[int]:
	var tokens := value.split(",")
	var result: Array[int] = []
	for index in 3:
		result.append(
			int(clampf(_numeric(tokens[index]), 0.0, 255.0)) if index < tokens.size() else 0
		)
	return result


static func dice_colours(value: Variant) -> Array:
	if not value is String or value.is_empty():
		return []
	var decoded: Variant = JSON.parse_string(value)
	if (
		not decoded is Dictionary
		or decoded.get("c2array") != true
		or not decoded.get("data") is Array
	):
		return []
	var result := []
	for item: Variant in decoded.data:
		if item is Array and not item.is_empty() and item[0] is Array and not item[0].is_empty():
			result.append(rgb(str(item[0][0])))
		else:
			result.append([0, 0, 0])
	return result


static func _numeric(value: Variant) -> float:
	if value is int or value is float:
		return float(value) if is_finite(float(value)) else 0.0
	if value is String:
		var number: float = value.to_float()
		return number if is_finite(number) else 0.0
	return 0.0


static func _draw_before(a: Dictionary, b: Dictionary) -> bool:
	return a.slot[0] < b.slot[0] or (a.slot[0] == b.slot[0] and a.slot[1] < b.slot[1])


static func tile_polygon(cell: int, facts: Dictionary) -> PackedInt64Array:
	var points := PackedInt64Array()
	var id := cell & Reader.TILE_ID_MASK
	if cell == -1 or float(id) in facts.collision_disabled:
		return points
	var polygon: Array = facts.collision_polygons.get(str(id), [0, 0, 1, 0, 1, 1, 0, 1])
	var width := int(facts.tile_size[0]) * S
	var height := int(facts.tile_size[1]) * S
	for index in range(0, polygon.size(), 2):
		# Quantize physical vertices once, not intermediate tile fractions.
		var x := roundi(polygon[index] * width)
		var y := roundi(polygon[index + 1] * height)
		if cell & Reader.FLIPPED_DIAGONAL:
			var swap := x
			x = y
			y = swap
		if cell & Reader.FLIPPED_HORIZONTAL:
			x = width - x
		if cell & Reader.FLIPPED_VERTICAL:
			y = height - y
		points.append(x)
		points.append(y)
	return points


static func tile_bounds(cell: int, facts: Dictionary) -> Array:
	return polygon_bounds(tile_polygon(cell, facts))


static func polygon_bounds(points: PackedInt64Array) -> Array:
	if points.is_empty():
		return []
	var left := points[0]
	var top := points[1]
	var right := left
	var bottom := top
	for index in range(2, points.size(), 2):
		left = mini(left, points[index])
		top = mini(top, points[index + 1])
		right = maxi(right, points[index])
		bottom = maxi(bottom, points[index + 1])
	return [left, top, right, bottom]


static func overlaps(world: Dictionary, x: int, y: int) -> bool:
	return overlaps_box(world, x - 12 * S, y - 56 * S, x + 12 * S, y)


static func overlaps_box(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	for layer: Dictionary in world.layers:
		if layer.solid and layer_overlaps(layer, left, top, right, bottom):
			return true
	return false


static func water_at(world: Dictionary, x: int, y: int) -> bool:
	return water_overlaps(world, x, y, x, y)


static func water_overlaps(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	for layer: Dictionary in world.layers:
		if layer.water and layer_overlaps(layer, left, top, right, bottom):
			return true
	return false


static func named_overlaps(
	world: Dictionary, tilemap_name: String, left: int, top: int, right: int, bottom: int
) -> bool:
	for layer: Dictionary in world.layers:
		if layer.name == tilemap_name and layer.layer != "layer3":
			if layer_overlaps(layer, left, top, right, bottom):
				return true
	return false


static func layer_overlaps(layer: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	var size: int = layer.size * S
	# Contact includes edges, including the far edge of the preceding cell.
	var x0 := maxi(0, floor_div(left - 1, size))
	var x1 := mini(layer.width - 1, floor_div(right, size))
	var y0 := maxi(0, floor_div(top - 1, size))
	var y1 := mini(layer.height - 1, floor_div(bottom, size))
	for row in range(y0, y1 + 1):
		for column in range(x0, x1 + 1):
			var cell: int = layer.cells[row * layer.width + column]
			var box: Array = layer.bounds.get(cell, [])
			if box.is_empty():
				continue
			var local_left := left - column * size
			var local_top := top - row * size
			var local_right := right - column * size
			var local_bottom := bottom - row * size
			if (
				local_left <= box[2]
				and local_right >= box[0]
				and local_top <= box[3]
				and local_bottom >= box[1]
				and Polygon.overlaps_box(
					layer.polygons[cell], local_left, local_top, local_right, local_bottom
				)
			):
				return true
	return false


static func floor_div(value: int, divisor: int) -> int:
	return value / divisor - int(value < 0 and value % divisor != 0)
