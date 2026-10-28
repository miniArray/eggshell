extends RefCounted
## Optional pack scenery: a wall that scrolls 1:1 with terrain, wall-mounted supports under
## every terrain underside that faces open air, and sprites for placed objects.
## Drawing only: nothing here reads input or writes play state.

const Frames = preload("res://src/view/pack_frames.gd")
const State = preload("res://src/sim/play_state.gd")
const Reader = preload("res://src/level/level_code.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
const Registry = preload("res://src/sim/registry.gd")
const World = preload("res://src/sim/world.gd")
const Decor = preload("res://src/sim/types/decor.gd")
const Ledges = preload("res://src/sim/types/decor_platform.gd")
const SnowTree = preload("res://src/sim/types/snow_tree.gd")
const Pack = preload("res://src/level/asset_pack.gd")
## Objects the simulation already places and moves; the view draws them from their state.
const SIMULATED := ["e1", "e2", "e3", "e5", "e20", "o5", "o11", "p1"]
const BOARD_HEIGHT := 6.0
const BACK_TINT := Color(0.84, 0.82, 0.78)
const WALL_Z := -20
const BRACKET_Z := -15
static var _frames := Frames.new()
static var _diagnostic: Texture2D
static var _placeholders := {}


static func load_texture(path: String) -> Texture2D:
	if path.begins_with("res://"):
		# Exported PNGs are imported Texture2D resources, not raw image files in the PCK.
		return ResourceLoader.load(path, "Texture2D") as Texture2D
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null else null


static func object_art(
	manifest: Dictionary, pack: String, code: String, variant := 0
) -> Dictionary:
	var objects: Dictionary = manifest.get("objects", {})
	var entry: Variant = objects.get(code, {})
	if entry is Dictionary and entry.get("variants") is Dictionary:
		entry = entry.variants.get(str(variant), entry)
	return _frames.visual(pack, entry, int(manifest.get("density", 1)))


static func sprite(art: Dictionary, z: int) -> Sprite2D:
	var node := Sprite2D.new()
	Frames.set_density(node, int(art.get("density", 1)))
	node.texture = art.texture
	node.centered = false
	node.offset = -art.origin
	node.set_meta("pack_art", art)
	node.z_index = z
	return node


static func bottom_anchored(art: Dictionary) -> bool:
	return art.origin.y >= art.texture.get_height() - 0.5


static func room(root: Node2D, manifest: Dictionary, pack: String, world: Dictionary) -> void:
	if not manifest.has("background"):
		return
	var size := Vector2(world.width, world.height) / State.SCALE
	var density := int(manifest.get("density", 1))
	var background: Dictionary = manifest.background
	strip(
		root,
		load_texture(pack.path_join(background.wall)),
		Rect2(Vector2.ZERO, size),
		WALL_Z,
		density
	)
	var counter := load_texture(pack.path_join(background.counter))
	if counter != null:
		var counter_height := float(counter.get_height()) / density
		strip(
			root,
			counter,
			Rect2(0, size.y - counter_height, size.x, counter_height),
			WALL_Z + 1,
			density
		)
	var cabinet := load_texture(pack.path_join(background.cabinet))
	if cabinet != null:
		strip(
			root,
			cabinet,
			Rect2(0, 0, size.x, float(cabinet.get_height()) / density),
			WALL_Z + 1,
			density
		)


static func strip(root: Node2D, texture: Texture2D, rect: Rect2, z: int, density: int = 1) -> void:
	if texture == null:
		return
	var node := Sprite2D.new()
	node.texture = texture
	node.centered = false
	node.region_enabled = true
	Frames.set_density(node, density)
	node.region_rect = Rect2(Vector2.ZERO, rect.size * density)
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	node.position = rect.position
	node.z_index = z
	root.add_child(node)


static func supports(root: Node2D, manifest: Dictionary, pack: String, world: Dictionary) -> void:
	if not manifest.has("supports"):
		return
	var shelf := load_texture(pack.path_join(manifest.supports.shelf))
	var bracket := load_texture(pack.path_join(manifest.supports.bracket))
	if shelf == null or bracket == null:
		return
	var density := int(manifest.get("density", 1))
	var facts: Dictionary = CollisionTable.read().tilemaps
	var bottom := float(world.height) / State.SCALE
	for group: String in ["layer2", "layer1"]:
		var solids: Array = world.layers.filter(
			func(layer: Dictionary) -> bool: return layer.layer == group and layer.solid
		)
		var tint := BACK_TINT if group == "layer2" else Color.WHITE
		var z := 5 if group == "layer2" else 7
		var runs := {}
		for layer: Dictionary in solids:
			for row in layer.height:
				for column in layer.width:
					var cell: int = layer.cells[row * layer.width + column]
					if cell == -1:
						continue
					var polygon := cell_polygon(cell, layer, facts, column, row)
					for index in polygon.size():
						var a := polygon[index]
						var b := polygon[(index + 1) % polygon.size()]
						var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
						var middle := (a + b) / 2.0
						if Geometry2D.is_point_in_polygon(middle + normal * 0.5, polygon):
							normal = -normal
						var probe := middle + Vector2(0, 2)
						if normal.y < 0.3 or probe.y >= bottom or solid_at(probe, solids, facts):
							continue
						if absf(a.y - b.y) < 0.01:
							var key := roundi(a.y)
							if not runs.has(key):
								runs[key] = []
							runs[key].append(Vector2(minf(a.x, b.x), maxf(a.x, b.x)))
						else:
							brace(root, shelf, a, b, normal, tint, z, density)
		for y: int in runs:
			for run: Vector2 in merged(runs[y]):
				board(root, shelf, bracket, run, y, tint, z, density)


static func cell_polygon(
	cell: int, layer: Dictionary, facts: Dictionary, column: int, row: int
) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var tile: Dictionary = facts[layer.name]
	var id := cell & Reader.TILE_ID_MASK
	if float(id) in tile.collision_disabled:
		return polygon
	var coordinates: Array = tile.collision_polygons.get(str(id), [0, 0, 1, 0, 1, 1, 0, 1])
	for index in range(0, coordinates.size(), 2):
		var x: float = coordinates[index]
		var y: float = coordinates[index + 1]
		if cell & Reader.FLIPPED_DIAGONAL:
			var swap := x
			x = y
			y = swap
		if cell & Reader.FLIPPED_HORIZONTAL:
			x = 1.0 - x
		if cell & Reader.FLIPPED_VERTICAL:
			y = 1.0 - y
		polygon.append(Vector2(column + x, row + y) * float(layer.size))
	return polygon


static func solid_at(point: Vector2, solids: Array, facts: Dictionary) -> bool:
	for layer: Dictionary in solids:
		var column := floori(point.x / layer.size)
		var row := floori(point.y / layer.size)
		if column < 0 or row < 0 or column >= layer.width or row >= layer.height:
			continue
		var cell: int = layer.cells[row * layer.width + column]
		if cell == -1:
			continue
		var polygon := cell_polygon(cell, layer, facts, column, row)
		if not polygon.is_empty() and Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


static func merged(segments: Array) -> Array:
	segments.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var result := []
	for segment: Vector2 in segments:
		if not result.is_empty() and segment.x <= result[-1].y + 0.5:
			result[-1] = Vector2(result[-1].x, maxf(result[-1].y, segment.y))
		else:
			result.append(segment)
	return result


static func board(
	root: Node2D,
	shelf: Texture2D,
	bracket: Texture2D,
	run: Vector2,
	y: float,
	tint: Color,
	z: int,
	density: int = 1
) -> void:
	# The board sits inside the terrain's bottom edge, never in the open space below it.
	var height := BOARD_HEIGHT if density == 1 else float(shelf.get_height()) / density
	var scale := height / shelf.get_height()
	var node := Sprite2D.new()
	if density > 1:
		node.set_meta("pack_density", density)
	node.texture = shelf
	node.centered = false
	node.region_enabled = true
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	node.region_rect = Rect2(0, 0, (run.y - run.x) / scale, shelf.get_height())
	node.scale = Vector2(scale, scale)
	node.position = Vector2(run.x, y - height)
	node.z_index = z
	node.modulate = tint
	root.add_child(node)
	var length := run.y - run.x
	var spots: Array[float] = []
	if length < 48.0:
		spots.append(run.x + length / 2.0)
	else:
		spots.append(run.x + 12.0)
		var x := run.x + 108.0
		while x < run.y - 48.0:
			spots.append(x)
			x += 96.0
		spots.append(run.y - 12.0)
	for spot: float in spots:
		# Brackets are flat on the wall plane, behind the player and terrain.
		var piece := Sprite2D.new()
		Frames.set_density(piece, density)
		piece.texture = bracket
		piece.centered = false
		piece.flip_h = spot > run.x + length / 2.0
		piece.offset = Vector2(-bracket.get_width() / 2.0, 0)
		piece.position = Vector2(spot, y)
		piece.z_index = BRACKET_Z
		piece.modulate = tint
		root.add_child(piece)


static func brace(
	root: Node2D,
	shelf: Texture2D,
	a: Vector2,
	b: Vector2,
	normal: Vector2,
	tint: Color,
	z: int,
	density: int = 1
) -> void:
	# A sloped underside becomes the diagonal brace of a bracket, drawn inside the terrain.
	var height := BOARD_HEIGHT if density == 1 else float(shelf.get_height()) / density
	var scale := height / shelf.get_height()
	var node := Sprite2D.new()
	if density > 1:
		node.set_meta("pack_density", density)
	node.texture = shelf
	node.region_enabled = true
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	node.region_rect = Rect2(0, 0, a.distance_to(b) / scale, shelf.get_height())
	node.scale = Vector2(scale, scale)
	node.rotation = (b - a).angle()
	node.position = (a + b) / 2.0 - normal * height / 2.0
	node.z_index = z
	node.modulate = tint
	root.add_child(node)


static func placeholder(name: String, size: int) -> Texture2D:
	# The same stable diagnostic squares used for terrain and enemies.
	var key := "%s:%d" % [name, size]
	if not _placeholders.has(key):
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color.from_hsv(float(absi(name.hash()) % 360) / 360.0, 0.55, 0.65))
		_placeholders[key] = ImageTexture.create_from_image(image)
	return _placeholders[key]


static func placed(root: Node2D, manifest: Dictionary, pack: String, world: Dictionary) -> void:
	var sources := {}
	var enemy_ids := {}
	for enemy: Dictionary in world.get("enemies", []):
		enemy_ids[enemy.id] = true
	for source: Dictionary in world.get("entities", []):
		sources[source.id] = source
	var level: Dictionary = world.source
	var map: Dictionary = world.get("map_source", level.maps["map%d" % int(level.startpoint.map)])
	for id: String in map.objects:
		var object: Dictionary = map.objects[id]
		var code: String = object.A
		if code in SIMULATED or enemy_ids.has(id):
			continue
		var initial := Registry.create(sources[id], world) if sources.has(id) else {"code": code}
		var node: Sprite2D
		if sources.has(id) and sources[id].has("decor"):
			node = _decoration(manifest, pack, sources[id], world)
		else:
			var art := object_art(manifest, pack, code, int(object.get("F", 0)))
			if art.is_empty() and not Registry.implemented(code):
				continue
			node = (
				_diagnostic_body(Registry.lookup(code), initial)
				if art.is_empty()
				else sprite(art, 8)
			)
			node.z_index = int(sources.get(id, {}).get("layer", 8))
			node.rotation_degrees = float(object.get("R", 0))
			node.flip_h = int(object.get("M", 0)) == 1
			node.set_meta("pack_variant", int(object.get("F", 0)))
			if code == "o23" and not art.is_empty():
				var parsed := Decor.size_option(object.get("E1", 64))
				var tall: float = parsed.get("value", 64.0)
				node.scale = Vector2(
					minf(32.0 / art.texture.get_width(), 2.0 / int(art.get("density", 1))),
					tall / art.texture.get_height()
				)
			if art.get("anchor", "box") == "position" and node.flip_h:
				node.flip_h = false
				node.scale.x *= -1
		node.set_meta("placed_id", id)
		node.set_meta("placed_code", code)
		node.set_meta("placed_source", object)
		node.position = Vector2(float(object.X), float(object.Y))
		node.visible = _entity_visible(initial)
		_remember_look(node)
		root.add_child(node)


static func decor_entry(manifest: Dictionary, code: String, variant: int) -> Dictionary:
	var objects: Dictionary = manifest.get("objects", {})
	var value: Variant = objects.get(code, {})
	if not value is Dictionary:
		return {}
	var entry: Dictionary = value.duplicate(true)
	if entry.get("variants") is Dictionary:
		var selected: Variant = entry.variants.get(str(variant))
		if selected is Dictionary:
			entry = selected.duplicate(true)
	elif code == "d22":
		var selected := _part_entry(entry, 1 if variant == 0 else 0)
		if not selected.is_empty():
			entry = selected
	if not entry.get("animations", {}) is Dictionary:
		return {}
	if code in ["d29", "d30"]:
		var name := "Standalone%d" % (1 if code == "d29" else 2)
		if entry.get("animations", {}).has(name):
			entry.default_animation = name
	if code in ["d25", "d26"]:
		var base := str(entry.get("default_animation", ""))
		var states: Variant = entry.get("states", {})
		var aliases: Dictionary = states.duplicate() if states is Dictionary else {}
		if base.length() >= 3:
			for color in 2:
				for style in 4:
					var name := str(color) + base.substr(1, base.length() - 2) + str(style)
					var key := "%s:%d:%d" % ["lit" if style < 2 else "dim", color, style % 2]
					if not aliases.has(key) and entry.get("animations", {}).has(name):
						aliases[key] = name
		entry.states = aliases
	return _ping_pong(entry)


static func decoration_plan(
	source: Dictionary, manifest: Dictionary, world: Dictionary = {}
) -> Array:
	var code: String = source.code
	var options: Dictionary = source.decor
	var index := code.substr(1).to_int()
	var entry := decor_entry(manifest, code, options.variant)
	var body := _part(entry)
	body.variant = options.variant
	var result := [body]
	if code in Ledges.CODES and entry.is_empty():
		body.boxes = Ledges.solid_boxes(
			{"code": code, "x": 0, "y": 0, "decor_variant": options.variant, "decor_mirror": 0}
		)
	if index >= 9 and index <= 13:
		result.append_array(_context_parts(source, manifest, world))
	if not Decor.resized(code):
		return result
	body.height = options.height
	body.resize = true
	body.bottom = true
	if index >= 14 and index <= 21:
		body.margins = [16, 16, 64, 0]
		result.append(_part(_visual_animation(manifest, "Stem%d" % (index - 13))))
	elif index >= 31 and index <= 54:
		body.margins = [0, 0, 32 if index >= 39 and index <= 46 else 64, 0]
		result.append(_part(_visual_animation(manifest, "CurlyStem%d" % ((index - 30) % 8))))
	elif index == 22:
		body.margins = [0, 96, 160, 0] if options.variant == 0 else [0, 160, 256, 32]
		body.height = maxf(options.height, 160 if options.variant == 0 else 290)
		body.position.y = (
			(16.0 if options.height < 160 else 0.0) if options.variant == 0 else 1264.0 / 71.0
		)
	elif index == 23:
		body.resize = false
		var pillar := _part(_part_entry(entry, 1))
		pillar.resize = true
		pillar.height = options.height
		pillar.bottom = false
		pillar.position.y = 32 if options.variant == 0 else 64
		pillar.tile = true
		result.push_front(pillar)
	elif index in [27, 28]:
		body.margins = [16, 16, 0, 32] if index == 27 else [16, 16, 32, 0]
		body.bottom = index == 28
		body.position.y = -16 if index == 27 else 16
		var lantern := _part(decor_entry(manifest, "d29", 0))
		lantern.animation = "Hanging" if index == 27 else "Standing"
		lantern.position.y = body.position.y + options.height * (1 if index == 27 else -1)
		result.append(lantern)
		if index == 28:
			var cap_name := str(entry.get("source_type", ""))
			result.append(_part(_visual_animation(manifest, cap_name), Vector2(0, 16)))
	elif index >= 56 and index <= 67:
		body.position.y = 16
		body.margins = [0, 112, 66, 30] if index <= 60 else [0, 80, 64, 0]
	elif index == 75:
		body.margins = [0, 0, 16, 16]
	return result


static func _context_parts(source: Dictionary, manifest: Dictionary, world: Dictionary) -> Array:
	if not world.has("layers"):
		return []
	# This drawing-only seam uses the canonical box, like diagnostic actor art.
	var sizes := {
		"d9": [64, 92, 32, 44],
		"d10": [48, 92, 24, 44],
		"d11": [64, 48, 32, 32],
		"d12": [64, 48, 32, 32],
		"d13": [32, 48, 16, 32]
	}
	var shape: Array = sizes[source.code]
	var bounds := [Decor.MAX_COORD, Decor.MAX_COORD, -Decor.MAX_COORD, -Decor.MAX_COORD]
	for x: int in [-shape[2], shape[0] - shape[2]]:
		for y: int in [-shape[3], shape[1] - shape[3]]:
			var point := Vector2(-x if source.decor.mirror else x, y).rotated(
				deg_to_rad(source.decor.rotation)
			)
			var px: int = source.x + roundi(point.x * State.SCALE)
			var py: int = source.y + roundi(point.y * State.SCALE)
			bounds = [
				mini(bounds[0], px), mini(bounds[1], py), maxi(bounds[2], px), maxi(bounds[3], py)
			]
	var result := []
	for pair: Array in [["cave64", "Default"], ["cave64_1", "Blue"], ["cave64_2", "Red"]]:
		if World.named_overlaps(world, pair[0], bounds[0], bounds[1], bounds[2], bounds[3]):
			var part := _part(_context_entry(manifest))
			part.animation = pair[1]
			part.variant = source.decor.variant
			part.position = Vector2(
				8 if source.code == "d10" else 0, 48 if source.code in ["d9", "d10"] else 16
			)
			# The attachment point mirrors, but spawned art keeps its own width.
			part.counter_mirror = bool(source.decor.mirror)
			result.append(part)
	return result


static func _context_entry(manifest: Dictionary) -> Dictionary:
	var visuals: Variant = manifest.get("visuals", {})
	if not visuals is Dictionary:
		return {}
	for value: Variant in visuals.values():
		if not value is Dictionary or not value.get("animations") is Dictionary:
			continue
		if ["Default", "Blue", "Red"].all(
			func(name: String) -> bool: return value.animations.has(name)
		):
			return value.duplicate(true)
	return {}


static func _part(entry: Dictionary, position := Vector2.ZERO) -> Dictionary:
	return {
		"entry": entry,
		"position": position,
		"resize": false,
		"height": 0.0,
		"bottom": false,
		"margins": [0, 0, 0, 0],
		"tile": false,
		"animation": "",
		"variant": 0
	}


static func _part_entry(entry: Dictionary, index: int) -> Dictionary:
	var types: Variant = entry.get("source_types", [])
	var parts: Variant = entry.get("parts", {})
	if (
		not types is Array
		or not parts is Dictionary
		or index < 0
		or index >= types.size()
		or not Pack.number_ok(types[index])
	):
		return {}
	var value: Variant = parts.get(str(int(types[index])), {})
	return value.duplicate(true) if value is Dictionary else {}


static func _visual_animation(manifest: Dictionary, animation: String) -> Dictionary:
	var visuals: Variant = manifest.get("visuals", {})
	if animation.is_empty() or not visuals is Dictionary:
		return {}
	for value: Variant in visuals.values():
		if (
			value is Dictionary
			and value.get("animations", {}) is Dictionary
			and value.get("animations", {}).has(animation)
		):
			var result: Dictionary = value.duplicate(true)
			result.default_animation = animation
			return _ping_pong(result)
	return {}


static func _ping_pong(entry: Dictionary) -> Dictionary:
	var animations: Variant = entry.get("animations", {})
	if not animations is Dictionary:
		return entry
	for value: Variant in animations.values():
		if not value is Dictionary or not value.get("frames") is Array:
			continue
		if value.get("ping_pong", false) == true and value.frames.size() > 2:
			for index in range(value.frames.size() - 2, 0, -1):
				value.frames.append(value.frames[index].duplicate(true))
			value.ping_pong = false
	return entry


static func _decoration(
	manifest: Dictionary, pack: String, source: Dictionary, world: Dictionary
) -> Sprite2D:
	var node := Sprite2D.new()
	node.set_meta("decor", true)
	node.z_index = int(source.decor.layer)
	node.rotation_degrees = float(source.decor.rotation)
	node.scale.x = -1 if source.decor.mirror else 1
	var bounds := Rect2()
	for part: Dictionary in decoration_plan(source, manifest, world):
		if part.has("boxes"):
			for box: Array in part.boxes:
				var rect := Rect2(
					Vector2(box[0], box[1]) / State.SCALE,
					Vector2(box[2] - box[0], box[3] - box[1]) / State.SCALE
				)
				var line := _marker(rect.size, Vector2.ZERO)
				line.position = rect.position
				node.add_child(line)
				bounds = bounds.merge(rect) if bounds.has_area() else rect
		else:
			var child := _draw_part(part, pack)
			node.add_child(child)
			var rect: Rect2 = child.get_meta("part_bounds", Rect2())
			bounds = bounds.merge(rect) if bounds.has_area() else rect
	node.set_meta("look_size", Vector2(maxf(1, bounds.size.x), maxf(1, bounds.size.y)))
	if source.code == "d22":
		var puff_art := _frames.visual(pack, _visual_animation(manifest, "BigDustNoDelay"))
		var puffs: Array[Sprite2D] = []
		for index in 8:
			var puff := (
				_marker(Vector2(8, 8), Vector2(4, 4))
				if puff_art.is_empty()
				else sprite(puff_art, 0)
			)
			puff.visible = false
			puff.z_as_relative = false
			puff.z_index = 14
			node.add_child(puff)
			puffs.append(puff)
		node.set_meta("puff_nodes", puffs)
	return node


static func _draw_part(part: Dictionary, pack: String) -> Node2D:
	var root := Node2D.new()
	root.position = part.position
	var art := _frames.visual(pack, part.entry)
	var frame: Dictionary = (
		view_sample(art, 0, {"animation": part.animation}, part.variant)
		if not art.is_empty()
		else {}
	)
	var native: Vector2 = frame.texture.get_size() if not frame.is_empty() else Vector2(12, 12)
	var height: float = part.height if part.resize else native.y
	var origin: Vector2 = frame.origin if not frame.is_empty() else native / 2
	if part.resize:
		origin = Vector2(native.x / 2, height if part.bottom else 0)
	var rectangle := Rect2(-origin, Vector2(native.x, height))
	root.set_meta("part_bounds", Rect2(root.position + rectangle.position, rectangle.size))
	if part.resize and not art.is_empty() and not part.tile:
		var patch := NinePatchRect.new()
		patch.texture = frame.texture
		patch.position = rectangle.position
		patch.patch_margin_left = int(part.margins[0])
		patch.patch_margin_right = int(part.margins[1])
		patch.patch_margin_top = int(part.margins[2])
		patch.patch_margin_bottom = int(part.margins[3])
		patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
		patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		patch.size = rectangle.size
		root.add_child(patch)
	else:
		var image := _marker(rectangle.size, origin) if art.is_empty() else sprite(art, 0)
		image.set_meta("pack_variant", part.variant)
		image.set_meta("part_animation", part.animation)
		if part.get("counter_mirror", false):
			image.scale.x *= -1
		if not frame.is_empty():
			image.texture = frame.texture
			image.offset = -frame.origin
		if part.resize and not art.is_empty():
			image.region_enabled = true
			image.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			image.region_rect = Rect2(Vector2.ZERO, rectangle.size)
			image.offset = -origin
			image.remove_meta("pack_art")
		root.add_child(image)
	return root


static func _body_rect(type: Script, entity: Dictionary) -> Rect2:
	var fallback := Rect2(-6, -6, 12, 12)
	if not type.has_method("bounds"):
		return fallback
	var box: Variant = type.call("bounds", entity)
	if (
		not box is Array
		or box.size() != 4
		or not box.all(func(value: Variant) -> bool: return Pack.number_ok(value))
	):
		return fallback
	if box[2] < box[0] or box[3] < box[1]:
		return fallback
	return Rect2(
		Vector2(box[0], box[1]) / State.SCALE,
		Vector2(float(box[2]) - box[0], float(box[3]) - box[1]) / State.SCALE
	)


static func _diagnostic_body(type: Script, entity: Dictionary) -> Sprite2D:
	var rect := _body_rect(type, entity)
	var node := _marker(rect.size, -rect.position, placeholder(entity.code, 12))
	node.set_meta("diagnostic_body", true)
	return node


static func _entity_visible(entity: Dictionary) -> bool:
	return (
		not entity.get("collected", 0) and not entity.get("held", 0) and not entity.get("hidden", 0)
	)


static func _marker(size: Vector2, origin: Vector2, texture: Texture2D = null) -> Sprite2D:
	if _diagnostic == null:
		# Generated diagnostic box, shared by all placements without pack art.
		var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_diagnostic = ImageTexture.create_from_image(image)
	var node := Sprite2D.new()
	node.texture = _diagnostic if texture == null else texture
	node.centered = false
	_marker_geometry(node, size, origin)
	return node


static func _marker_geometry(node: Sprite2D, size: Vector2, origin: Vector2) -> void:
	node.scale = size / 12.0
	node.offset = Vector2(
		-origin.x * 12.0 / size.x if size.x > 0 else -6.0,
		-origin.y * 12.0 / size.y if size.y > 0 else -6.0
	)


static func _remember_look(node: Sprite2D) -> void:
	var size: Vector2 = node.get_meta(
		"look_size", node.texture.get_size() if node.texture != null else Vector2.ONE
	)
	var art: Dictionary = node.get_meta("pack_art", {})
	var position_anchor: bool = (
		node.get_meta("decor", false) or art.get("anchor", "box") == "position"
	)
	node.set_meta(
		"base_look",
		{
			"size": size,
			"scale": node.scale,
			"rotation": node.rotation_degrees,
			"alpha": node.modulate.a,
			"flip_h": node.flip_h,
			"position_anchor": position_anchor
		}
	)


static func look_plan(base: Dictionary, look: Dictionary) -> Dictionary:
	var result := base.duplicate()
	var position: Vector2 = base.position
	var scale: Vector2 = base.scale
	for axis: String in ["x", "y"]:
		var offset: Variant = look.get("offset_" + axis)
		var size: Variant = look.get("size_" + axis)
		var component := 0 if axis == "x" else 1
		if Pack.number_ok(offset):
			position[component] += float(offset)
		if Pack.number_ok(size) and size >= 0:
			scale[component] = (
				(-1 if base.scale[component] < 0 else 1)
				* float(size)
				/ maxf(0.0001, base.size[component])
			)
	if look.get("flip_x") is bool:
		if base.get("position_anchor", false):
			scale.x = (-1 if look.flip_x else 1) * absf(scale.x)
			result.flip_h = false
		else:
			result.flip_h = look.flip_x
	if Pack.number_ok(look.get("rotation")):
		result.rotation = fposmod(float(look.rotation), 360.0)
	if Pack.number_ok(look.get("modulate_alpha")):
		result.alpha = clampf(float(look.modulate_alpha), 0, 1)
	if look.get("visible") is bool:
		result.visible = look.visible
	result.position = position
	result.scale = scale
	return result


static func view_sample(art: Dictionary, tick: int, look: Dictionary, variant := 0) -> Dictionary:
	if art.is_empty():
		return {}
	var animation := str(look.get("animation", ""))
	var name: String = (
		animation
		if art.animations.has(animation)
		else str(
			art.states.get(
				"%s:%d" % [animation, variant], art.states.get(animation, art.default_animation)
			)
		)
	)
	if not art.animations.has(name):
		name = art.default_animation
	if look.get("frame") is int:
		var frames: Array = art.animations[name].frames
		return frames[clampi(look.frame, 0, frames.size() - 1)]
	if art.animations.has(animation):
		return Frames.sample(
			{"animations": art.animations, "default_animation": name, "states": {}},
			tick,
			"",
			variant
		)
	return Frames.sample(art, tick, animation, variant)


static func update_placed(node: Sprite2D, entity: Dictionary, state: Dictionary) -> void:
	var type: Script = Registry.lookup(entity.code)
	var look: Dictionary = (
		type.call("view_state", entity, state) if type.has_method("view_state") else {}
	)
	var base: Dictionary = node.get_meta("base_look", {})
	if base.is_empty():
		_remember_look(node)
		base = node.get_meta("base_look")
	base = base.duplicate()
	base.position = Vector2(entity.x, entity.y) / State.SCALE
	base.visible = _entity_visible(entity)
	if node.get_meta("diagnostic_body", false):
		var rect := _body_rect(type, entity)
		_marker_geometry(node, rect.size, -rect.position)
		base.scale = node.scale
	if node.has_meta("pack_art"):
		_apply_look_frame(node, state.frame, look)
		base.size = node.texture.get_size()
	var pose := look_plan(base, look)
	node.position = pose.position
	node.scale = pose.scale
	node.rotation_degrees = pose.rotation
	node.z_index = int(entity.layer)
	node.modulate.a = pose.alpha
	node.visible = pose.visible and not entity.get("held", 0) and not entity.get("hidden", 0)
	node.flip_h = pose.flip_h
	if node.get_meta("decor", false):
		for part: Node in node.get_children():
			for child: Node in part.get_children():
				if child is Sprite2D and child.has_meta("pack_art"):
					var part_look := look.duplicate()
					if not str(child.get_meta("part_animation", "")).is_empty():
						part_look.animation = child.get_meta("part_animation")
					_apply_look_frame(child, state.frame, part_look)
		if entity.code == "d22":
			var puffs := SnowTree.puffs(entity, state.frame)
			var nodes: Array = node.get_meta("puff_nodes", [])
			for index in nodes.size():
				var puff: Sprite2D = nodes[index]
				puff.visible = index < puffs.size()
				if puff.visible:
					puff.position = (
						Vector2(puffs[index].x - entity.x, puffs[index].y - entity.y) / State.SCALE
					)
					_apply_look_frame(puff, puffs[index].age, {"frame": puffs[index].age / 15})


static func _apply_look_frame(node: Sprite2D, tick: int, look: Dictionary) -> void:
	if not node.has_meta("pack_art"):
		return
	var art: Dictionary = node.get_meta("pack_art")
	var frame := view_sample(art, tick, look, int(node.get_meta("pack_variant", 0)))
	node.texture = frame.texture
	node.offset = -frame.origin
