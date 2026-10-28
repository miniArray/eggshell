extends Node2D
## Draws pack strips along open terrain edges in art pixels. Slopes step one art pixel
## at a time: each column (or row, for sides) is a whole strip slice moved by whole art
## pixels. Nothing rotates, scales or blends, so every strip pixel keeps its own colour.
## Drawing only: nothing here reads input or writes play state.

const Edges = preload("res://src/view/terrain_edges.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
## Draw order: sides first, surfaces last, so a surface lip covers a wall's top corner.
const ORDER := [Edges.LEFT, Edges.RIGHT, Edges.UNDERSIDE, Edges.SURFACE]
var _runs: Array = []
var _strips: Dictionary = {}


## `strips` maps surface, underside and side to {texture, edge}. `edge` is the number of strip
## rows above the edge line (columns left of it for a side), in art pixels.
func setup(runs: Array, strips: Dictionary, density: int, z: int) -> void:
	_runs = runs
	_strips = strips
	scale = Vector2.ONE / density
	z_index = z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


func _draw() -> void:
	for kind: String in ORDER:
		var strip: Dictionary = _strips.get(
			"side" if kind == Edges.LEFT or kind == Edges.RIGHT else kind, {}
		)
		if strip.is_empty():
			continue
		for run: Dictionary in _runs:
			if run.kind == kind:
				draw_run(run, strip)


func draw_run(run: Dictionary, strip: Dictionary) -> void:
	var texture: Texture2D = strip.texture
	var size := Vector2i(texture.get_size())
	var edge: int = strip.edge
	var line: PackedInt32Array = run.line
	var index := 0
	while index < line.size():
		# Neighbouring slices on the same line become one rectangle.
		var count := 1
		while index + count < line.size() and line[index + count] == line[index]:
			count += 1
		var along := int(run.start) + index
		match run.kind:
			Edges.SURFACE, Edges.UNDERSIDE:
				draw_texture_rect_region(
					texture,
					Rect2(along, line[index] - edge, count, size.y),
					Rect2(posmod(along, size.x), 0, count, size.y)
				)
			Edges.LEFT:
				draw_texture_rect_region(
					texture,
					Rect2(line[index] - edge, along, size.x, count),
					Rect2(0, posmod(along, size.y), size.x, count)
				)
			Edges.RIGHT:
				# The side strip is drawn for an open side facing left; mirror it, never rotate.
				draw_texture_rect_region(
					texture,
					Rect2(line[index] + edge - size.x, along, size.x, count),
					Rect2(size.x, posmod(along, size.y), -size.x, count)
				)
		index += count


## Adds one strip node per dressed tile layer, drawn just above that layer's tiles.
## Packs without a `terrain` section add nothing, so their drawing is unchanged.
static func dress(
	root: Node2D, manifest: Dictionary, pack: String, world: Dictionary, layers: Array
) -> void:
	var terrain: Dictionary = manifest.get("terrain", {})
	if terrain.is_empty():
		return
	var density := int(manifest.get("density", 1))
	var facts: Dictionary = CollisionTable.read().tilemaps
	var script: GDScript = load("res://src/view/terrain_strips.gd")
	for index in layers.size():
		var layer: Dictionary = layers[index]
		var entry := entry_for(terrain, layer.name)
		if entry.is_empty() or not (layer.solid or layer.water):
			continue
		var strips := {}
		for part: String in ["surface", "underside", "side"]:
			if not entry.has(part):
				continue
			var texture := Dressing.load_texture(pack.path_join(entry[part].file))
			var edge := int(entry[part].get("edge", 0))
			if (
				texture == null
				or edge > (texture.get_width() if part == "side" else texture.get_height())
			):
				printerr("Terrain strip ignored: %s %s" % [layer.name, part])
				continue
			strips[part] = {"texture": texture, "edge": edge}
		if strips.is_empty():
			continue
		var runs := Edges.find(world, layers, [layer.name], facts, density).filter(
			func(run: Dictionary) -> bool: return run.layer == index
		)
		var node: Node2D = script.new()
		node.name = "TerrainStrips_" + layer.name
		node.setup(runs, strips, density, int(layer.slot[0]))
		root.add_child(node)


## A tilemap's own entry wins over its family's: `garden32_1` falls back to `garden32`.
static func entry_for(terrain: Dictionary, tilemap: String) -> Dictionary:
	if terrain.get(tilemap) is Dictionary:
		return terrain[tilemap]
	var family := RegEx.create_from_string("_[0-9]+$").sub(tilemap, "")
	var entry: Variant = terrain.get(family, {})
	return entry if entry is Dictionary else {}
