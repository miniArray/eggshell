class_name LevelCode
extends RefCounted
## Pure JSON level-code reader. No file or engine-state access.
## Success: {"ok": true, "level": Dictionary}. Failure: {"ok": false, "error": String}.
## Original fields and dictionary order survive. Tilemap strings become dictionaries

const TILE_ID_MASK := 0x1fffffff
const FLIPPED_HORIZONTAL := 0x80000000
const FLIPPED_VERTICAL := 0x40000000
const FLIPPED_DIAGONAL := 0x20000000
# Bound untrusted expansion before allocating.
const MAX_CELLS := 4_000_000
const MAX_LEVEL_CELLS := 16_000_000
const MAX_CODE_BYTES := 16_777_216


static func parse(code: String) -> Dictionary:
	if code.to_utf8_buffer().size() > MAX_CODE_BYTES:
		return _error("Level code exceeds the 16 MiB limit")
	var parsed := _json_object(code, "Level")
	if not parsed.ok:
		return parsed
	var level: Dictionary = parsed.value
	# An absent author can be exported as numeric zero. Keep display text usable.
	if _number(level.get("author")):
		level.author = String.num(float(level.author)).trim_suffix(".0")
	for field in ["version", "name", "desc", "author"]:
		if not level.get(field) is String:
			return _error("Level.%s must be a string" % field)
	for field: String in ["flowers", "redcoins"]:
		var value: Variant = level.get(field, 0)
		if not _number(value) or value < -0x80000000 or value > 0x7fffffff or floor(value) != value:
			return _error("Level.%s must be a bounded integer" % field)
		level[field] = int(value)
	if not level.get("startpoint") is Dictionary:
		return _error("Level.startpoint must be an object")
	var start: Dictionary = level.startpoint
	if not _positive_integer(start.get("map")):
		return _error("Level.startpoint.map must be a positive integer")
	if not _number(start.get("X")) or not _number(start.get("Y")):
		return _error("Level.startpoint.X and Y must be finite numbers")
	if not level.get("maps") is Dictionary or level.maps.is_empty():
		return _error("Level.maps must be a non-empty object")
	if not level.maps.has("map%d" % int(start.map)):
		return _error("Level.startpoint references a missing map")
	var total_cells := 0
	for map_name: String in level.maps:
		var map_number := map_name.trim_prefix("map")
		if not map_name.begins_with("map") or not map_number.is_valid_int():
			return _error("Map keys must use map followed by a positive integer")
		if int(map_number) < 1 or str(int(map_number)) != map_number:
			return _error("Map keys must use map followed by a positive integer")
		if not level.maps[map_name] is Dictionary:
			return _error("%s must be an object" % map_name)
		var map: Dictionary = level.maps[map_name]
		if not _positive_integer(map.get("width")) or not _positive_integer(map.get("height")):
			return _error("%s width and height must be positive integers" % map_name)
		if not map.get("objects") is Dictionary:
			return _error("%s.objects must be an object" % map_name)
		for object_id: String in map.objects:
			var object: Variant = map.objects[object_id]
			if not object is Dictionary or not object.get("A") is String:
				return _error("%s.objects.%s must have a string A" % [map_name, object_id])
			if not _number(object.get("X")) or not _number(object.get("Y")):
				return _error("%s.objects.%s must have finite X and Y" % [map_name, object_id])
		_normalize_objects(map.objects, level.version)
		for layer_name in ["layer1", "layer2", "layer3"]:
			if not map.has(layer_name):
				continue
			if not map[layer_name] is Dictionary:
				return _error("%s.%s must be an object" % [map_name, layer_name])
			var layer: Dictionary = map[layer_name]
			for tilemap_name: String in layer:
				var path := "%s.%s.%s" % [map_name, layer_name, tilemap_name]
				if not layer[tilemap_name] is String:
					return _error("%s must be a JSON tilemap string" % path)
				var tile_result := decode_tilemap(
					layer[tilemap_name], MAX_LEVEL_CELLS - total_cells
				)
				if not tile_result.ok:
					return _error("%s: %s" % [path, tile_result.error])
				layer[tilemap_name] = tile_result.tilemap
				total_cells += tile_result.tilemap.cells.size()
	return {"ok": true, "level": level}


static func revision(version: String) -> Array[int]:
	var result: Array[int] = []
	if not version.begins_with("s"):
		return result
	for part: String in version.substr(1).split("."):
		if not part.is_valid_int() or int(part) < 0:
			return []
		result.append(int(part))
	return result


static func _normalize_objects(objects: Dictionary, version: String) -> void:
	# This legacy gate compares writer strings, not numeric revision components.
	if version >= "s3.8":
		return
	for object: Dictionary in objects.values():
		if object.A == "o14" and object.get("E1", "") == "1":
			object.F = 1
			object.erase("E1")


static func decode_tilemap(code: String, remaining_cells: int = MAX_CELLS) -> Dictionary:
	var parsed := _json_object(code, "Tilemap")
	if not parsed.ok:
		return parsed
	var tilemap: Dictionary = parsed.value
	if tilemap.get("c2tilemap") != true:
		return _error("Tilemap.c2tilemap must be true")
	if not _positive_integer(tilemap.get("width")) or not _positive_integer(tilemap.get("height")):
		return _error("Tilemap width and height must be positive integers")
	if tilemap.width > MAX_CELLS or tilemap.height > MAX_CELLS:
		return _error("Tilemap exceeds the cell limit")
	var count := int(tilemap.width) * int(tilemap.height)
	if count > mini(MAX_CELLS, remaining_cells):
		return _error("Tilemap exceeds the cell limit")
	if not tilemap.get("data") is String:
		return _error("Tilemap.data must be a run-length string")
	# `cells` is reader-owned. Refuse a collision rather than lose an unknown field.
	if tilemap.has("cells"):
		return _error("Tilemap contains the reserved reader field cells")
	var token_pattern := RegEx.new()
	token_pattern.compile("^(?:([1-9][0-9]*)x)?(-1|[0-9]+)([hvd]*)$")
	var cells := PackedInt32Array()
	cells.resize(count)
	var cursor := 0
	for token: String in tilemap.data.split(",", true):
		var match_token := token_pattern.search(token)
		if match_token == null:
			return _error("Invalid tile run: %s" % token.left(80))
		var repeat_text := match_token.get_string(1)
		# Compare digit lengths before converting so huge integers cannot overflow.
		if repeat_text.length() > 10:
			return _error("Tile run exceeds the cell count")
		var repeat := 1 if repeat_text.is_empty() else repeat_text.to_int()
		if repeat > count - cursor:
			return _error("Tile runs exceed width * height")
		var id_text := match_token.get_string(2)
		if id_text.length() > 10:
			return _error("Tile ID exceeds the tile identifier mask")
		var value := id_text.to_int()
		if value > TILE_ID_MASK:
			return _error("Tile ID exceeds the tile identifier mask")
		var flags := match_token.get_string(3)
		if value == -1 and not flags.is_empty():
			return _error("Empty tile cannot have flags")
		for flag in ["h", "v", "d"]:
			if flags.count(flag) > 1:
				return _error("Duplicate tile flag")
		if "h" in flags:
			value |= FLIPPED_HORIZONTAL
		if "v" in flags:
			value |= FLIPPED_VERTICAL
		if "d" in flags:
			value |= FLIPPED_DIAGONAL
		if value > 0x7fffffff:
			value -= 0x100000000
		_fill_run(cells, cursor, repeat, value)
		cursor += repeat
	if cursor != count:
		return _error("Tile runs decode to %d cells, expected %d" % [cursor, count])
	tilemap.cells = cells
	return {"ok": true, "tilemap": tilemap}


static func _fill_run(cells: PackedInt32Array, start: int, count: int, value: int) -> void:
	for index in range(start, start + count):
		cells[index] = value


static func _json_object(code: String, label: String) -> Dictionary:
	var json := JSON.new()
	var error := json.parse(code)
	if error != OK:
		return _error(
			"%s JSON line %d: %s" % [label, json.get_error_line(), json.get_error_message()]
		)
	if not json.data is Dictionary:
		return _error("%s must be a JSON object" % label)
	return {"ok": true, "value": json.data}


static func _positive_integer(value: Variant) -> bool:
	return _number(value) and value > 0 and value <= 0x7fffffff and floor(value) == value


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
