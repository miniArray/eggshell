extends SceneTree
## Real pack loading and world placement with generated density-two textures.
const InputPack = preload("res://tests/density_pack.gd")
const View = preload("res://src/view/level_view.gd")
const State = preload("res://src/sim/play_state.gd")
const Save = preload("res://src/save/snapshot.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const Hud = preload("res://src/view/hud.gd")
const Frames = preload("res://src/view/pack_frames.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := InputPack.create()
	var world := InputPack.world()
	var state := State.create(world)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.setup(world, path)
	var before := Save.encode(state)
	view.render(state)
	check(Save.encode(state) == before, "Drawing keeps simulation bytes unchanged")
	check(view._root.scale == Vector2(2, 2), "Density sets world scale")
	var tile: TileMapLayer
	for node in view._root.get_children():
		if node is TileMapLayer:
			tile = node
	check(tile.tile_set.tile_size == Vector2i(64, 64), "Atlas cells are art pixels")
	check(
		tile.tile_set.get_source(0).texture_region_size == Vector2i(64, 64),
		"Atlas cuts 64-pixel tiles"
	)
	check(
		tile.map_to_local(Vector2i(1, 0)) * tile.scale == Vector2(48, 16),
		"Tiles land on 32-world-pixel cells"
	)
	check(view._player.scale == Vector2(0.5, 0.5), "Player art is half world size")
	check(
		view._player.texture.get_size() * view._player.scale == Vector2(24, 56),
		"Player has world dimensions"
	)
	check(
		view._player.offset * view._player.scale == Vector2(-12, -56),
		"Player origin is in art pixels"
	)
	Frames.apply(view._player, 1)
	check(
		view._player.offset * view._player.scale == Vector2(-12.5, -55.5),
		"Animated frame origin keeps half-world-pixel precision"
	)
	Frames.apply(view._player, 0)
	var coin: Sprite2D = view._placed_nodes.coin
	check(coin.position == Vector2(200, 250), "Level positions stay in world pixels")
	check(coin.offset * coin.scale == Vector2(-3, -9), "Object origin is halved")
	check(coin.texture.get_size() * coin.scale == Vector2(8, 10), "Object art is halved")
	check(view._background._strips[0].height == 20, "Map gradient offset stays in world pixels")
	check(view._background._strips[1].height == 40, "Pack gradient heights use art pixels")
	var layer: Dictionary = view._background._layers[0]
	check(layer.scale == Vector2(0.5, 0.5), "Background texture size is halved")
	check(layer.anchor == Vector2(20, 30), "Background anchor is halved")
	check(layer.offset == Vector2(17, 21), "Background origin placement is halved")
	check(layer.reference == Vector2(40, 50), "Scroll reference is halved")
	check(layer.period == Vector2(16, 20), "Repeat spacing is halved")
	var bridge_found := false
	for node in view._root.get_children():
		if (
			node is Sprite2D
			and node.has_meta("pack_art")
			and not node.centered
			and node.position == Vector2(268, 284)
		):
			bridge_found = true
			check(
				node.scale.y == 0.5 and node.offset == Vector2(-6, -18),
				"Bridge height and origin use pack pixels"
			)
	check(bridge_found, "Bridge pack art is present")
	var manifest := Pack.read(path)
	var room := Node2D.new()
	Dressing.room(room, manifest, path, world)
	for sprite: Sprite2D in room.get_children():
		check(sprite.scale == Vector2(0.5, 0.5), "Room image density")
	check(room.get_child(1).position.y == 4086, "Counter height is in world pixels")
	room.free()
	var supports := Node2D.new()
	var shelf := Dressing.load_texture(path.path_join("shelf.png"))
	var bracket := Dressing.load_texture(path.path_join("object.png"))
	Dressing.board(supports, shelf, bracket, Vector2(0, 64), 100, Color.WHITE, 1, 2)
	check(supports.get_child(0).scale == Vector2(0.5, 0.5), "Shelf density")
	check(supports.get_child(0).position == Vector2(0, 94), "Shelf height is halved")
	check(supports.get_child(1).scale == Vector2(0.5, 0.5), "Bracket density")
	supports.free()
	for sprite: Sprite2D in view._enemy_nodes:
		check(sprite.scale.abs() == Vector2(0.5, 0.5), "Position-anchored enemy density")
	for sprite in view._root.get_children():
		if sprite.has_meta("goal"):
			check(
				sprite.scale == Vector2(0.5, 0.5) and sprite.offset == Vector2(-6, -18),
				"Goal size and origin"
			)
	# Fractional simulation positions and odd art origins must still hit screen pixels.
	for factor: float in [2.0, 4.0, 6.0]:
		for rotation: float in [0.0, PI / 2, PI, 3 * PI / 2]:
			for mirror: int in [-1, 1]:
				var sprite := Dressing.sprite(Dressing.object_art(manifest, path, "o1"), 1)
				sprite.position = Vector2(123.123, 234.567)
				sprite.rotation = rotation
				sprite.scale.x *= mirror
				Frames.snap(sprite, factor)
				var corner := (
					(sprite.position + sprite.transform.basis_xform(sprite.get_rect().position))
					* factor
				)
				check(
					corner.is_equal_approx(corner.round()),
					"Rotated/mirrored sprite corner lands on screen pixels"
				)
				sprite.free()
	var transforms := {}
	for node in view._root.get_children():
		if node is Sprite2D:
			transforms[node.get_instance_id()] = node.transform
	viewport.size = Vector2i(3840, 2160)
	view.render(state)
	viewport.size = Vector2i(1920, 1080)
	view.render(state)
	for node in view._root.get_children():
		if node is Sprite2D:
			check(
				node.transform.is_equal_approx(transforms[node.get_instance_id()]),
				"Resizing does not accumulate snap or scale drift"
			)
	var hud := view.get_node("RunHud")
	check(hud._bubble.scale == Vector2(0.5, 0.5), "Recovery/bubble art density")
	check(hud._bubble.offset == Vector2(-6, -18), "Recovery/bubble origin")
	for size: Vector2 in [Vector2(170, 80), Vector2(64, 64), Vector2(1, 1)]:
		var plan := Hud.dense_plan(size, [40.0, 40.0, 40.0, 40.0], [16.0, 16.0, 16.0, 16.0], 1)
		check(plan.scale == 1.0, "Tiny HUD never drops art pixels")
		check(plan.positions[0].y == floorf(minf(8, size.x / 16)), "Health stays first and at top")
		check(plan.positions[1].y >= plan.positions[0].y, "HUD wraps instead of shrinking")
	viewport.free()
	InputPack.remove(path)
	print("PACK_DENSITY_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
