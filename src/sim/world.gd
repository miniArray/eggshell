class_name SimWorld
extends RefCounted

const Reader = preload("res://src/level/level_code.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Maps = preload("res://src/sim/maps.gd")
const S := preload("res://src/sim/units.gd").SCALE
# Every tilemap of the deadly lava family. Players, enemies and items share this list.
## Terrain chunk edge for the static terrain lookup cache.
const CHUNK := 256 * S
## A probe covering more chunks than this reads every layer, as before the cache.
const MAX_CHUNKS := 16
## Remembered terrain probe answers per map before the memory starts over.
const MAX_TERRAIN_HITS := 1 << 16
const LAVA_LAYERS := ["lava", "lava_1", "lava_2", "lava_3", "lava_4"]
const SPIKE_LAYER := "ySSpikes"
## Each side of a map has a solid border 32 px wide, from 480 px above the map down to
## its bottom edge. It keeps bodies inside the map; below the map the sides are open.
const BORDER_WIDTH := 32 * S
const BORDER_ABOVE := 480 * S


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
		# Transient lookup caches for this map's static terrain; never saved.
		compiled.world.terrain_chunks = {}
		compiled.world.terrain_hits = {}
		compiled.world.terrain_escapes = {}
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


static func _build_objects(_map: Dictionary, world: Dictionary) -> Dictionary:
	return setup_objects(world.map_source, world)


static func setup_objects(map: Dictionary, world: Dictionary) -> Dictionary:
	# Late binding keeps the level compiler independent of type behavior imports.
	var registry: Script = load("res://src/sim/registry.gd")
	return registry.compile_map(map.get("objects", {}), world)


static func _load_layers(map: Dictionary, world: Dictionary, facts: Dictionary) -> Dictionary:
	for layer_name: String in ["layer2", "layer1", "layer3"]:
		for name: String in map.get(layer_name, {}):
			if not facts.tilemaps.has(name):
				return {"ok": false, "error": "Unsupported tilemap: " + name}
			var tile: Dictionary = facts.tilemaps[name]
			if tile.tile_size[0] != tile.tile_size[1]:
				# Cell lookup assumes square cells; refuse rather than misplace terrain.
				return {"ok": false, "error": "Unsupported tile shape: " + name}
			var grid: Dictionary = map[layer_name][name]
			var slot := []
			for instance: Dictionary in tile.get("instances", []):
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
				# Draw order never blocks play: use the diagnostic layer2-before-layer1 slot.
				slot = [0 if layer_name == "layer2" else 1, world.layers.size()]
			var bounds := {}
			var polygons := {}
			var rectangles := {}
			if tile.solid_family or tile.water_family or name in LAVA_LAYERS or name == SPIKE_LAYER:
				for cell: int in grid.cells:
					if cell != -1 and not bounds.has(cell):
						var points := tile_polygon(cell, tile)
						polygons[cell] = points
						bounds[cell] = polygon_bounds(points)
						if axis_rectangle(points):
							rectangles[cell] = true
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
					"rectangles": rectangles,
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


## Terrain never changes after loading, so a map remembers recent answers per probe box.
## Bodies held inside terrain repeat the same push-out probes every step.
## Solid terrain or a side border.
static func overlaps_box(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	return (
		border_overlaps(world, left, top, right, bottom)
		or tiles_overlap_box(world, left, top, right, bottom)
	)


## Solid terrain tiles only, without the side borders.
static func tiles_overlap_box(
	world: Dictionary, left: int, top: int, right: int, bottom: int
) -> bool:
	var hits: Variant = world.get("terrain_hits")
	var key := [left, top, right, bottom]
	if hits != null:
		var known: Variant = hits.get(key)
		if known != null:
			return known
	var hit := false
	for layer: Dictionary in layers_near(world, left, top, right, bottom):
		if layer.solid and layer_overlaps(layer, left, top, right, bottom):
			hit = true
			break
	if hits != null:
		if hits.size() >= MAX_TERRAIN_HITS:
			hits.clear()
		hits[key] = hit
	return hit


## True when the box reaches into a side border: past the map's left or right edge, beside
## the map or above it. A box that only touches an edge stays outside the border.
static func border_overlaps(
	world: Dictionary, left: int, top: int, right: int, bottom: int
) -> bool:
	if top >= world.get("height", 0) or bottom <= -BORDER_ABOVE:
		return false
	if left < 0 and right > -BORDER_WIDTH:
		return true
	var width: int = world.get("width", 0)
	return width > 0 and right > width and left < width + BORDER_WIDTH


## Layers, in draw order, that can answer layer_overlaps() true for this probe: those with
## a contact cell in a terrain chunk the probe touches. Any other layer only has empty or
## disabled cells there, so skipping it never changes a result. Terrain never changes after
## loading, so each chunk's list is computed once. Worlds without the cache get all layers.
static func layers_near(world: Dictionary, left: int, top: int, right: int, bottom: int) -> Array:
	var chunks: Variant = world.get("terrain_chunks")
	if chunks == null:
		return world.layers
	# layer_overlaps() reads cells touching [left - 1, right] x [top - 1, bottom].
	var cx0 := floor_div(left - 1, CHUNK)
	var cy0 := floor_div(top - 1, CHUNK)
	var cx1 := floor_div(right, CHUNK)
	var cy1 := floor_div(bottom, CHUNK)
	if cx1 < cx0 or cy1 < cy0 or (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > MAX_CHUNKS:
		return world.layers
	if cx0 == cx1 and cy0 == cy1:
		return _chunk_layers(world, chunks, cx0, cy0)
	var found := {}
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			for index: int in _chunk_indices(world, chunks, cx, cy):
				found[index] = true
	var indices := found.keys()
	indices.sort()
	var result := []
	for index: int in indices:
		result.append(world.layers[index])
	return result


static func _chunk_layers(world: Dictionary, chunks: Dictionary, cx: int, cy: int) -> Array:
	_chunk_indices(world, chunks, cx, cy)
	return chunks[_chunk_key(cx, cy)][1]


static func _chunk_indices(world: Dictionary, chunks: Dictionary, cx: int, cy: int) -> Array:
	var key := _chunk_key(cx, cy)
	var entry: Variant = chunks.get(key)
	if entry != null:
		return entry[0]
	var indices := []
	var layers := []
	for index in world.layers.size():
		var layer: Dictionary = world.layers[index]
		if layer.bounds.is_empty():
			continue
		var size: int = layer.size * S
		# A cell's closed span reaches its far edge, so include one cell before the chunk.
		var x0 := maxi(0, floor_div(cx * CHUNK, size) - 1)
		var x1 := mini(layer.width - 1, floor_div((cx + 1) * CHUNK - 1, size))
		var y0 := maxi(0, floor_div(cy * CHUNK, size) - 1)
		var y1 := mini(layer.height - 1, floor_div((cy + 1) * CHUNK - 1, size))
		var hit := false
		for row in range(y0, y1 + 1):
			for column in range(x0, x1 + 1):
				var box: Variant = layer.bounds.get(layer.cells[row * layer.width + column])
				if box != null and not box.is_empty():
					hit = true
					break
			if hit:
				break
		if hit:
			indices.append(index)
			layers.append(layer)
	chunks[key] = [indices, layers]
	return indices


static func _chunk_key(cx: int, cy: int) -> int:
	return (cx << 32) ^ (cy & 0xffffffff)


static func water_at(world: Dictionary, x: int, y: int) -> bool:
	return water_overlaps(world, x, y, x, y)


static func water_overlaps(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	for layer: Dictionary in layers_near(world, left, top, right, bottom):
		if layer.water and layer_overlaps(layer, left, top, right, bottom):
			return true
	return false


static func named_overlaps(
	world: Dictionary, tilemap_name: String, left: int, top: int, right: int, bottom: int
) -> bool:
	for layer: Dictionary in layers_near(world, left, top, right, bottom):
		if layer.name == tilemap_name and layer.layer != "layer3":
			if layer_overlaps(layer, left, top, right, bottom):
				return true
	return false


static func lava_overlaps(world: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	for name: String in LAVA_LAYERS:
		if named_overlaps(world, name, left, top, right, bottom):
			return true
	return false


static func layer_overlaps(layer: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	var size: int = layer.size * S
	var rectangles: Dictionary = layer.get("rectangles", {})
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
				and (
					rectangles.has(cell)
					or Polygon.overlaps_box(
						layer.polygons[cell], local_left, local_top, local_right, local_bottom
					)
				)
			):
				return true
	return false


## Like overlaps_box() for a polygon body: `points` in world units, `box` its bounds.
## The side borders stay boxes.
static func overlaps_polygon(world: Dictionary, points: PackedInt64Array, box: Array) -> bool:
	if border_overlaps(world, box[0], box[1], box[2], box[3]):
		return true
	for layer: Dictionary in layers_near(world, box[0], box[1], box[2], box[3]):
		if not layer.solid:
			continue
		var size: int = layer.size * S
		var x0 := maxi(0, floor_div(box[0] - 1, size))
		var x1 := mini(layer.width - 1, floor_div(box[2], size))
		var y0 := maxi(0, floor_div(box[1] - 1, size))
		var y1 := mini(layer.height - 1, floor_div(box[3], size))
		for row in range(y0, y1 + 1):
			for column in range(x0, x1 + 1):
				var cell: int = layer.cells[row * layer.width + column]
				if layer.bounds.get(cell, []).is_empty():
					continue
				var local := PackedInt64Array()
				local.resize(points.size())
				for index in range(0, points.size(), 2):
					local[index] = points[index] - column * size
					local[index + 1] = points[index + 1] - row * size
				if Polygon.overlaps_polygon(local, layer.polygons[cell]):
					return true
	return false


## A closed axis-aligned rectangle with positive area: four corners, each edge along one
## axis. For such a polygon, Polygon.overlaps_box equals the inclusive bounds test, which
## layer_overlaps() has already passed, so the polygon test can be skipped.
static func axis_rectangle(points: PackedInt64Array) -> bool:
	if points.size() != 8:
		return false
	var box := polygon_bounds(points)
	if box[0] >= box[2] or box[1] >= box[3]:
		return false
	var corners := {}
	for index in range(0, 8, 2):
		var next := (index + 2) % 8
		var x := points[index]
		var y := points[index + 1]
		if (x != box[0] and x != box[2]) or (y != box[1] and y != box[3]):
			return false
		if (x != points[next]) == (y != points[next + 1]):
			return false
		corners["%d,%d" % [x, y]] = true
	return corners.size() == 4


static func floor_div(value: int, divisor: int) -> int:
	return value / divisor - int(value < 0 and value % divisor != 0)
