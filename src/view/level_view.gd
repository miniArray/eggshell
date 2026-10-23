extends Node2D

const Motion = preload("res://src/sim/enemy_motion.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const State = preload("res://src/sim/play_state.gd")
const Plan = preload("res://src/view/screen_plan.gd")
const Reader = preload("res://src/level/level_code.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const PLAYER_COLOR := Color("ffffff")  # Placeholder specification: plain player box.
const GOAL_COLOR := Color("ffd43b")  # Generated diagnostic goal marker.
var _world: Dictionary
var _root := Node2D.new()
var _player := Sprite2D.new()
var _animations := {}
var _goal_label := Label.new()
var _last_texture: Texture2D
var _spring_nodes: Array[Sprite2D] = []
var _enemy_nodes: Array[Sprite2D] = []
var _head_nodes: Array[Sprite2D] = []
var _recovery_marker := Sprite2D.new()


func setup(world: Dictionary, pack: String) -> void:
	_world = world
	add_child(_root)
	var manifest := Pack.read(pack)
	var layers: Array = world.layers.duplicate(true)
	if not manifest.is_empty():
		for layer: Dictionary in layers:
			if not manifest.drawing.tilemaps.has(layer.name):
				continue
			for instance: Dictionary in manifest.drawing.tilemaps[layer.name].instances:
				if (
					(layer.layer == "layer1" and instance.layer.ends_with("L1"))
					or (layer.layer == "layer2" and instance.layer.ends_with("L2"))
				):
					layer.slot = [int(instance.layer_index), int(instance.z_order)]
		layers.sort_custom(draw_before)
	for layer: Dictionary in layers:
		var texture: Texture2D
		if not manifest.is_empty() and manifest.tiles.has(layer.name):
			texture = load_texture(pack.path_join(manifest.tiles[layer.name]))
		var real_tiles := texture != null
		if texture == null:
			texture = placeholder(layer.name, layer.size)
		var atlas := TileSetAtlasSource.new()
		atlas.texture = texture
		atlas.texture_region_size = Vector2i(layer.size, layer.size)
		var columns: int = texture.get_width() / layer.size
		var tiles := TileSet.new()
		tiles.tile_size = Vector2i(layer.size, layer.size)
		tiles.add_source(atlas, 0)
		var node := TileMapLayer.new()
		node.set_meta("water", bool(layer.water))
		node.tile_set = tiles
		node.z_index = layer.slot[0]
		_root.add_child(node)
		for row in layer.height:
			for column in layer.width:
				var cell: int = layer.cells[row * layer.width + column]
				if cell == -1:
					continue
				var id := cell & Reader.TILE_ID_MASK
				var coords := Vector2i(id % columns, id / columns)
				if not real_tiles:
					if layer.bounds.get(cell, []).is_empty():
						continue
					coords = Vector2i.ZERO
				if not atlas.has_tile(coords):
					atlas.create_tile(coords)
				var flags := 0
				if cell & Reader.FLIPPED_HORIZONTAL:
					flags |= TileSetAtlasSource.TRANSFORM_FLIP_H
				if cell & Reader.FLIPPED_VERTICAL:
					flags |= TileSetAtlasSource.TRANSFORM_FLIP_V
				if cell & Reader.FLIPPED_DIAGONAL:
					flags |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
				node.set_cell(Vector2i(column, row), 0, coords, flags)
	if not manifest.is_empty():
		for name: String in manifest.player:
			var animation: Dictionary = manifest.player[name]
			var frames := []
			for frame: Dictionary in animation.frames:
				frames.append(
					{
						"texture": load_texture(pack.path_join(frame.file)),
						"origin": Vector2(frame.origin[0], frame.origin[1])
					}
				)
			_animations[name] = {"frames": frames, "speed": animation.speed}
	for name: String in ["Idle0", "Walk0", "Sprint0", "Jump0", "Fall0", "Flutter0"]:
		if not _animations.has(name) or _animations[name].frames.is_empty():
			_animations.clear()
			break
		for frame: Dictionary in _animations[name].frames:
			if frame.texture == null:
				_animations.clear()
				break
		if _animations.is_empty():
			break
	# The v2 pack has no object frames. Reuse diagnostic flat textures, not new art.
	for spring: Dictionary in world.springs:
		var size := 48 if spring.large else 32
		var node := Sprite2D.new()
		node.texture = placeholder("o11", size)
		node.centered = false
		node.offset = Vector2(-size / 2.0, -size)
		node.z_index = 10
		_root.add_child(node)
		_spring_nodes.append(node)
	for bridge: Dictionary in world.bridges:
		var node := Sprite2D.new()
		node.texture = placeholder("p1", 32)
		node.centered = false
		node.position = Vector2(bridge.left, bridge.top) / State.SCALE
		node.scale.x = float(bridge.right - bridge.left) / (32 * State.SCALE)
		node.z_index = 10
		_root.add_child(node)
	for enemy: Dictionary in world.enemies:
		var node := Sprite2D.new()
		node.texture = placeholder(enemy.code, 32)
		node.centered = false
		node.z_index = 10
		_root.add_child(node)
		_enemy_nodes.append(node)
		var head := Sprite2D.new()
		head.texture = node.texture
		head.centered = false
		head.z_index = 10
		_root.add_child(head)
		_head_nodes.append(head)
	_player.centered = false
	_player.z_index = 11
	_root.add_child(_player)
	# Use the sprite shader already exercised at spawn. An untextured polygon
	# introduces a new GLES3 shader variant when the distant goal enters view.
	var goal_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	goal_image.fill(GOAL_COLOR)
	var goal_texture := ImageTexture.create_from_image(goal_image)
	for goal: Array in world.goals:
		var marker := Sprite2D.new()
		marker.texture = goal_texture
		marker.z_index = 10
		marker.set_meta("goal", true)
		marker.position = Vector2(goal[0], goal[1]) / State.SCALE
		_root.add_child(marker)
	# Recovery first appears mid-run; share the same generated texture and warmed shader.
	_recovery_marker.texture = goal_texture
	_recovery_marker.z_index = 12
	_recovery_marker.set_meta("recovery", true)
	_root.add_child(_recovery_marker)
	var background: PackedStringArray = world.bgcolor.split(",")
	if background.size() == 3:
		RenderingServer.set_default_clear_color(
			Color(
				float(background[0]) / 255.0,
				float(background[1]) / 255.0,
				float(background[2]) / 255.0
			)
		)
	_goal_label.text = "Goal"
	_goal_label.visible = false
	add_child(_goal_label)
	if _animations.is_empty():
		var image := Image.create(24, 56, false, Image.FORMAT_RGBA8)
		image.fill(PLAYER_COLOR)
		_player.texture = ImageTexture.create_from_image(image)
		_player.offset = Vector2(-12, -56)


func render(state: Dictionary) -> void:
	var viewport := get_viewport_rect().size
	var focus := Vector2(state.camera_x, state.camera_y) / State.SCALE
	var plan := Plan.plan(viewport, Vector2(_world.width, _world.height) / State.SCALE, focus)
	_root.scale = Vector2.ONE * plan.scale
	_root.position = plan.offset
	_player.position = Vector2(state.x, state.y) / State.SCALE
	for index in _spring_nodes.size():
		var ball: Dictionary = state.springs[index]
		var node := _spring_nodes[index]
		var size := 48.0 if _world.springs[index].large else 32.0
		var squash: int = mini(ball.squash, 12 - ball.squash)
		node.position = Vector2(ball.x, ball.y) / State.SCALE
		node.visible = bool(ball.active)
		node.scale = Vector2((size + 16.0 * squash / 6) / size, (size - 16.0 * squash / 6) / size)
	for index in _enemy_nodes.size():
		var enemy: Dictionary = state.enemies[index]
		var code: String = _world.enemies[index].code
		var bounds := Motion.box(enemy, code)
		var node := _enemy_nodes[index]
		node.position = Vector2(enemy.x + bounds[0], enemy.y + bounds[1]) / State.SCALE
		node.scale = Vector2(bounds[2] - bounds[0], bounds[3] - bounds[1]) / (32 * State.SCALE)
		node.visible = enemy.status == 1
		var head := _head_nodes[index]
		head.visible = enemy.status == 1 and code == "e5" and enemy.mode != 0
		if head.visible:
			var head_bounds := Plant.head_box(enemy)
			head.position = Vector2(head_bounds[0], head_bounds[1]) / State.SCALE
			head.scale = (
				Vector2(head_bounds[2] - head_bounds[0], head_bounds[3] - head_bounds[1])
				/ (32 * State.SCALE)
			)
	_player.visible = (
		not state.captured_by and (not state.invulnerable or (120 - state.invulnerable) % 6 < 3)
	)
	_player.modulate.a = 0.5 if state.invulnerable else 1.0
	_recovery_marker.position = Vector2(state.recovery_x, state.recovery_y) / State.SCALE
	_recovery_marker.visible = state.separated and not state.recovery_delay
	if not _animations.is_empty():
		var name: String = ["Idle0", "Walk0", "Sprint0", "Jump0", "Fall0", "Idle0", "Flutter0"][
			state.movement
		]
		var animation: Dictionary = _animations[name]
		var index: int = int(state.frame * animation.speed / 60.0) % animation.frames.size()
		var frame: Dictionary = animation.frames[index]
		if frame.texture != _last_texture:
			_player.texture = frame.texture
			_last_texture = frame.texture
		_player.scale.x = state.facing
		_player.offset = -frame.origin
	_goal_label.visible = bool(state.goal_reached or state.separated)
	_goal_label.text = "Goal" if state.goal_reached else "Recover: %d" % state.health
	_goal_label.position = Vector2(8, 8)


static func draw_before(a: Dictionary, b: Dictionary) -> bool:
	return a.slot[0] < b.slot[0] or (a.slot[0] == b.slot[0] and a.slot[1] < b.slot[1])


static func load_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null else null


static func placeholder(name: String, size: int) -> Texture2D:
	# Stable per-tileset colors. These are diagnostic flat squares, not art.
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.from_hsv(float(absi(name.hash()) % 360) / 360.0, 0.55, 0.65))
	return ImageTexture.create_from_image(image)
