extends SceneTree
## GPU readback of terrain strips through the production view. Run without --headless.
## A generated pack draws a raised block on stacked ground. Surface strips must land on the
## open tops only, side strips on open walls (mirrored on the right), and internal joins
## must keep the plain fill.
const InputPack = preload("res://tests/density_pack.gd")
const View = preload("res://src/view/level_view.gd")
const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")
const FILL := Color8(10, 20, 200)
const SURFACE_EDGE := 2
const SIDE_EDGE := 1
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GPU check requires a rendering display, not --headless")
		quit(1)
		return
	var path := "/tmp/eggshell-terrain-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(path)
	var world := level_world()
	for density: int in [1, 2]:
		write_pack(path, density)
		for size: Vector2i in [Vector2i(640, 480), Vector2i(1920, 1080)]:
			var viewport := SubViewport.new()
			viewport.size = size
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			viewport.transparent_bg = true
			root.add_child(viewport)
			var view := View.new()
			viewport.add_child(view)
			view.setup(world, path)
			var state := State.create(world)
			state.camera_x = 192 * State.SCALE
			state.camera_y = 160 * State.SCALE
			view.render(state)
			var strips: Node2D
			for node in view._root.get_children():
				if node is CanvasItem:
					node.visible = node is TileMapLayer or node.name.begins_with("TerrainStrips")
				if node.name.begins_with("TerrainStrips"):
					strips = node
			view.get_node("RunHud").hide()
			view._effects.hide()
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			check(strips != null, "Terrain strips are added for the dressed tilemap")
			check_strips(strips, pixels, density)
			viewport.free()
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
	print("TERRAIN_RENDER_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check_strips(strips: Node2D, pixels: Image, density: int) -> void:
	var transform := strips.get_global_transform()
	var factor := roundi(transform.x.length())
	check(factor >= 1, "Every art pixel gets at least one screen pixel")
	var surface := strip_image(5, 6)
	var side := strip_image(4, 3)
	var tile := 32 * density
	# Block on cells 4-5 of row 4; ground fills rows 5-7 of a 12 by 8 cell map.
	for x in 12 * tile:
		var top := 4 * tile if x >= 4 * tile and x < 6 * tile else 5 * tile
		for y in surface.get_height():
			art_pixel(
				transform,
				factor,
				pixels,
				Vector2i(x, top - SURFACE_EDGE + y),
				surface.get_pixel(x % 5, y),
				"Surface strip on open top"
			)
		for join: int in [6 * tile, 7 * tile]:
			for y in range(join - 3, join + 3):
				art_pixel(
					transform, factor, pixels, Vector2i(x, y), FILL, "Internal join keeps the fill"
				)
	for y in range(4 * tile + 6 - SURFACE_EDGE, 5 * tile - SURFACE_EDGE):
		for x in side.get_width():
			var expected := side.get_pixel(x, y % 3)
			art_pixel(
				transform,
				factor,
				pixels,
				Vector2i(4 * tile - SIDE_EDGE + x, y),
				expected,
				"Left wall strip"
			)
			var mirrored := side.get_pixel(side.get_width() - 1 - x, y % 3)
			art_pixel(
				transform,
				factor,
				pixels,
				Vector2i(6 * tile + SIDE_EDGE - 4 + x, y),
				mirrored,
				"Right wall strip is mirrored"
			)


func art_pixel(
	transform: Transform2D,
	factor: int,
	pixels: Image,
	art: Vector2i,
	expected: Color,
	label: String
) -> void:
	var corner := transform * Vector2(art)
	if (
		corner.x < 0
		or corner.y < 0
		or corner.x + factor > pixels.get_width()
		or corner.y + factor > pixels.get_height()
	):
		return
	for sy in factor:
		for sx in factor:
			var at := Vector2i((corner + Vector2(sx + 0.5, sy + 0.5)).floor())
			check(pixels.get_pixelv(at).is_equal_approx(expected), label)


## Every pixel of a strip has its own colour, so a dropped, repeated or blended pixel shows.
static func strip_image(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			image.set_pixel(x, y, Color8(40 + 40 * x, 30 + 40 * y, 7, 255))
	return image


func write_pack(path: String, density: int) -> void:
	var tile := Image.create(32 * density, 32 * density, false, Image.FORMAT_RGBA8)
	tile.fill(FILL)
	tile.save_png(path.path_join("fill.png"))
	strip_image(5, 6).save_png(path.path_join("surface.png"))
	strip_image(4, 3).save_png(path.path_join("side.png"))
	InputPack.write_json(
		path,
		"manifest.json",
		{
			"version": 3,
			"density": density,
			"tiles": {"castle32": "fill.png"},
			"drawing_facts": "drawing_facts.json",
			"player": {},
			"terrain":
			{
				"castle32":
				{
					"surface": {"file": "surface.png", "edge": SURFACE_EDGE},
					"side": {"file": "side.png", "edge": SIDE_EDGE}
				}
			}
		}
	)
	InputPack.write_json(
		path,
		"drawing_facts.json",
		{
			"tilemaps":
			{"castle32": {"instances": [{"layer": "castle32L1", "layer_index": 0, "z_order": 0}]}}
		}
	)


static func level_world() -> Dictionary:
	var rows := [
		"............",
		"............",
		"............",
		"............",
		"....00......",
		"000000000000",
		"000000000000",
		"000000000000",
	]
	var tokens := []
	for row: String in rows:
		for character in row:
			tokens.append("-1" if character == "." else character)
	var map := {
		"width": 384,
		"height": 256,
		"objects": {},
		"layer1":
		{
			"castle32":
			JSON.stringify({"c2tilemap": true, "width": 12, "height": 8, "data": ",".join(tokens)})
		},
		"layer2": {},
		"bgcolor": "0,0,0",
	}
	var code := {
		"version": "1",
		"name": "Terrain",
		"desc": "",
		"author": "Eggshell",
		"startpoint": {"map": 1, "X": 32, "Y": 160},
		"flowers": 0,
		"redcoins": 0,
		"maps": {"map1": map},
	}
	var built := World.build(JSON.stringify(code), Collision.read())
	assert(built.ok, str(built))
	return built.world


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		if _failures <= 8:
			printerr("FAIL: " + label)
