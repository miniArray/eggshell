extends RefCounted
## Optional pack scenery: a wall that scrolls 1:1 with terrain, wall-mounted supports under
## every terrain underside that faces open air, and sprites for placed objects.
## Drawing only: nothing here reads input or writes play state.

const State = preload("res://src/sim/play_state.gd")
const Reader = preload("res://src/level/level_code.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
## Objects the simulation already places and moves; the view draws them from their state.
const SIMULATED := ["e1", "e2", "e3", "e5", "e20", "o5", "o11", "p1"]
const BOARD_HEIGHT := 6.0
const BACK_TINT := Color(0.84, 0.82, 0.78)
const WALL_Z := -20
const BRACKET_Z := -15


static func load_texture(path: String) -> Texture2D:
	if path.begins_with("res://"):
		# Exported PNGs are imported Texture2D resources, not raw image files in the PCK.
		return ResourceLoader.load(path, "Texture2D") as Texture2D
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null else null


static func object_art(manifest: Dictionary, pack: String, code: String) -> Dictionary:
	var objects: Dictionary = manifest.get("objects", {})
	if not objects.has(code):
		return {}
	var entry: Dictionary = objects[code]
	var texture := load_texture(pack.path_join(entry.file))
	if texture == null:
		return {}
	return {"texture": texture, "origin": Vector2(entry.origin[0], entry.origin[1])}


static func sprite(art: Dictionary, z: int) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture = art.texture
	node.centered = false
	node.offset = -art.origin
	node.z_index = z
	return node


static func bottom_anchored(art: Dictionary) -> bool:
	return art.origin.y >= art.texture.get_height() - 0.5


static func room(root: Node2D, manifest: Dictionary, pack: String, world: Dictionary) -> void:
	if not manifest.has("background"):
		return
	var size := Vector2(world.width, world.height) / State.SCALE
	var background: Dictionary = manifest.background
	strip(root, load_texture(pack.path_join(background.wall)), Rect2(Vector2.ZERO, size), WALL_Z)
	var counter := load_texture(pack.path_join(background.counter))
	if counter != null:
		var counter_height := float(counter.get_height())
		strip(root, counter, Rect2(0, size.y - counter_height, size.x, counter_height), WALL_Z + 1)
	var cabinet := load_texture(pack.path_join(background.cabinet))
	if cabinet != null:
		strip(root, cabinet, Rect2(0, 0, size.x, cabinet.get_height()), WALL_Z + 1)


static func strip(root: Node2D, texture: Texture2D, rect: Rect2, z: int) -> void:
	if texture == null:
		return
	var node := Sprite2D.new()
	node.texture = texture
	node.centered = false
	node.region_enabled = true
	node.region_rect = Rect2(Vector2.ZERO, rect.size)
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
							brace(root, shelf, a, b, normal, tint, z)
		for y: int in runs:
			for run: Vector2 in merged(runs[y]):
				board(root, shelf, bracket, run, y, tint, z)


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
	root: Node2D, shelf: Texture2D, bracket: Texture2D, run: Vector2, y: float, tint: Color, z: int
) -> void:
	# The board sits inside the terrain's bottom edge, never in the open space below it.
	var scale := BOARD_HEIGHT / shelf.get_height()
	var node := Sprite2D.new()
	node.texture = shelf
	node.centered = false
	node.region_enabled = true
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	node.region_rect = Rect2(0, 0, (run.y - run.x) / scale, shelf.get_height())
	node.scale = Vector2(scale, scale)
	node.position = Vector2(run.x, y - BOARD_HEIGHT)
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
		piece.texture = bracket
		piece.centered = false
		piece.flip_h = spot > run.x + length / 2.0
		piece.offset = Vector2(-bracket.get_width() / 2.0, 0)
		piece.position = Vector2(spot, y)
		piece.z_index = BRACKET_Z
		piece.modulate = tint
		root.add_child(piece)


static func brace(
	root: Node2D, shelf: Texture2D, a: Vector2, b: Vector2, normal: Vector2, tint: Color, z: int
) -> void:
	# A sloped underside becomes the diagonal brace of a bracket, drawn inside the terrain.
	var scale := BOARD_HEIGHT / shelf.get_height()
	var node := Sprite2D.new()
	node.texture = shelf
	node.region_enabled = true
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	node.region_rect = Rect2(0, 0, a.distance_to(b) / scale, shelf.get_height())
	node.scale = Vector2(scale, scale)
	node.rotation = (b - a).angle()
	node.position = (a + b) / 2.0 - normal * BOARD_HEIGHT / 2.0
	node.z_index = z
	node.modulate = tint
	root.add_child(node)


static func placed(root: Node2D, manifest: Dictionary, pack: String, world: Dictionary) -> void:
	# Objects without simulated behaviour still appear; touching them does nothing yet.
	var source: Dictionary = world.source
	var map: Dictionary = source.maps["map%d" % int(source.startpoint.map)]
	for object: Dictionary in map.objects.values():
		var code: String = object.A
		if code in SIMULATED:
			continue
		var art := object_art(manifest, pack, code)
		if art.is_empty():
			continue
		var node := sprite(art, 7 if code.begins_with("d") else 8)
		node.position = Vector2(float(object.X), float(object.Y))
		node.rotation_degrees = float(object.get("R", 0))
		node.flip_h = int(object.get("M", 0)) == 1
		if code == "o23":
			var tall := float(object.get("E1", 64))
			node.scale = Vector2(
				minf(32.0 / art.texture.get_width(), 2.0), tall / art.texture.get_height()
			)
		root.add_child(node)
