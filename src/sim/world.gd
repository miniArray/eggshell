class_name SimWorld
extends RefCounted

const Reader = preload("res://src/level/level_code.gd")
const State = preload("res://src/sim/play_state.gd")
const S := State.SCALE


static func build(code: String, facts: Dictionary) -> Dictionary:
	var parsed := Reader.parse(code)
	if not parsed.ok:
		return parsed
	var source: Dictionary = parsed.level
	var map: Dictionary = source.maps["map%d" % int(source.startpoint.map)]
	var world := {
		"identity": code.sha256_text(),
		"source": source,
		"width": int(map.width) * S,
		"height": int(map.height) * S,
		"spawn_x": roundi(source.startpoint.X * S),
		"spawn_y": roundi(source.startpoint.Y * S),
		"layers": [],
		"goals": [],
		"springs": [],
		"enemies": [],
		"bridges": [],
		"bgcolor": map.get("bgcolor", "255,214,173")
	}
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
	for layer_name: String in ["layer2", "layer1"]:
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
			if slot.is_empty():
				return {"ok": false, "error": "Missing source draw slot: " + name}
			var bounds := {}
			if tile.solid_family or tile.water_family:
				for cell: int in grid.cells:
					if cell != -1 and not bounds.has(cell):
						bounds[cell] = tile_bounds(cell, tile)
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
					"solid": tile.solid_family,
					"water": tile.water_family
				}
			)
	world.layers.sort_custom(_draw_before)
	return {"ok": true, "world": world}


static func _draw_before(a: Dictionary, b: Dictionary) -> bool:
	return a.slot[0] < b.slot[0] or (a.slot[0] == b.slot[0] and a.slot[1] < b.slot[1])


static func tile_bounds(cell: int, facts: Dictionary) -> Array:
	var id := cell & Reader.TILE_ID_MASK
	if float(id) in facts.collision_disabled:
		return []
	var polygon: Array = facts.collision_polygons.get(str(id), [0, 0, 1, 0, 1, 1, 0, 1])
	var left := S
	var top := S
	var right := 0
	var bottom := 0
	for index in range(0, polygon.size(), 2):
		var x := roundi(polygon[index] * S)
		var y := roundi(polygon[index + 1] * S)
		if cell & Reader.FLIPPED_DIAGONAL:
			var swap := x
			x = y
			y = swap
		if cell & Reader.FLIPPED_HORIZONTAL:
			x = S - x
		if cell & Reader.FLIPPED_VERTICAL:
			y = S - y
		left = mini(left, x)
		top = mini(top, y)
		right = maxi(right, x)
		bottom = maxi(bottom, y)
	var size := int(facts.tile_size[0])
	return [left * size, top * size, right * size, bottom * size]


static func overlaps(world: Dictionary, x: int, y: int) -> bool:
	return overlaps_box(world, x - 12 * S, y - 56 * S, x + 12 * S, y)


static func overlaps_box(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	for layer: Dictionary in world.layers:
		if not layer.solid:
			continue
		var size: int = layer.size * S
		var x0 := maxi(0, floor_div(left, size))
		var x1 := mini(layer.width - 1, floor_div(right - 1, size))
		var y0 := maxi(0, floor_div(top, size))
		var y1 := mini(layer.height - 1, floor_div(bottom - 1, size))
		for row in range(y0, y1 + 1):
			for column in range(x0, x1 + 1):
				var cell: int = layer.cells[row * layer.width + column]
				var box: Array = layer.bounds.get(cell, [])
				if box.is_empty():
					continue
				if (
					left < column * size + box[2]
					and right > column * size + box[0]
					and top < row * size + box[3]
					and bottom > row * size + box[1]
				):
					return true
	return false


static func water_at(world: Dictionary, x: int, y: int) -> bool:
	return water_overlaps(world, x, y, x + 1, y + 1)


static func water_overlaps(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	for layer: Dictionary in world.layers:
		if not layer.water:
			continue
		var size: int = layer.size * S
		for row in range(
			maxi(0, floor_div(top, size)), mini(layer.height - 1, floor_div(bottom - 1, size)) + 1
		):
			for column in range(
				maxi(0, floor_div(left, size)),
				mini(layer.width - 1, floor_div(right - 1, size)) + 1
			):
				var cell: int = layer.cells[row * layer.width + column]
				var box: Array = layer.bounds.get(cell, [])
				if (
					not box.is_empty()
					and left < column * size + box[2]
					and right > column * size + box[0]
					and top < row * size + box[3]
					and bottom > row * size + box[1]
				):
					return true
	return false


static func floor_div(value: int, divisor: int) -> int:
	return value / divisor - int(value < 0 and value % divisor != 0)
