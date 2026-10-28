extends Node2D

const Motion = preload("res://src/sim/enemy_motion.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const State = preload("res://src/sim/play_state.gd")
const Plan = preload("res://src/view/screen_plan.gd")
const Reader = preload("res://src/level/level_code.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const Frames = preload("res://src/view/pack_frames.gd")
const PlayerPose = preload("res://src/view/player_pose.gd")
const Background = preload("res://src/view/pack_background.gd")
const AudioMap = preload("res://src/view/pack_audio.gd")
const PLAYER_COLOR := Color("ffffff")  # Placeholder specification: plain player box.
const GOAL_COLOR := Color("ffd43b")  # Generated diagnostic goal marker.
var audio := AudioMap.new()
var _world: Dictionary
var _root := Node2D.new()
var _player := Sprite2D.new()
var _animations := {}
var _frames := Frames.new()
var _background := Background.new()
var _goal_label := Label.new()
var _spring_nodes: Array[Sprite2D] = []
var _enemy_nodes: Array[Sprite2D] = []
var _head_nodes: Array[Sprite2D] = []
var _recovery_marker := Sprite2D.new()


func setup(world: Dictionary, pack: String) -> void:
	_world = world
	add_child(_root)
	var manifest := Pack.read(pack)
	var source: Dictionary = world.source
	var map: Dictionary = source.maps["map%d" % int(source.startpoint.map)]
	audio.setup(manifest, pack)
	_background.setup(manifest, pack, map)
	_root.add_child(_background)
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
	if not manifest.is_empty() and not manifest.player.is_empty():
		var states := {}
		for name: String in manifest.player:
			states[name] = name
		_animations = (
			_frames
			. visual(
				pack,
				{
					"animations": manifest.player,
					"default_animation": "Idle0",
					"states": states,
				}
			)
		)
		if not _animations.is_empty():
			_player.set_meta("pack_art", _animations)
	Dressing.room(_root, manifest, pack, world)
	Dressing.supports(_root, manifest, pack, world)
	Dressing.placed(_root, manifest, pack, world)
	# Packs without object art keep the diagnostic flat textures.
	var spring_art := Dressing.object_art(manifest, pack, "o11")
	for spring: Dictionary in world.springs:
		var size := 48 if spring.large else 32
		var node: Sprite2D
		if spring_art.is_empty():
			node = Sprite2D.new()
			node.texture = placeholder("o11", size)
			node.centered = false
			node.offset = Vector2(-size / 2.0, -size)
			node.z_index = 10
			node.set_meta("base", 1.0)
		else:
			node = Dressing.sprite(spring_art, 10)
			node.set_meta("base", size / float(spring_art.texture.get_height()))
		node.set_meta("pack_variant", int(spring.large) + 2 * int(spring.single_use))
		if not spring_art.is_empty():
			Frames.apply(node, 0)
			node.set_meta("base", size / float(node.texture.get_height()))
		_root.add_child(node)
		_spring_nodes.append(node)
	var bridge_art := Dressing.object_art(manifest, pack, "p1")
	for bridge: Dictionary in world.bridges:
		var node := Sprite2D.new()
		var width := float(bridge.right - bridge.left) / State.SCALE
		node.centered = false
		node.position = Vector2(bridge.left, bridge.top) / State.SCALE
		node.z_index = 10
		if bridge_art.is_empty():
			node.texture = placeholder("p1", 32)
			node.scale.x = width / 32.0
		else:
			node.texture = bridge_art.texture
			node.scale.x = width / bridge_art.texture.get_width()
		_root.add_child(node)
	var head_art := Dressing.object_art(manifest, pack, "e5_head")
	for enemy: Dictionary in world.enemies:
		var art := Dressing.object_art(manifest, pack, enemy.code, int(enemy.variant))
		_enemy_nodes.append(actor_node(art, placeholder(enemy.code, 32)))
		_enemy_nodes[-1].set_meta("pack_variant", int(enemy.variant))
		_head_nodes.append(actor_node(head_art, _enemy_nodes[-1].texture))
	_player.centered = false
	_player.z_index = 11
	_root.add_child(_player)
	# Use the sprite shader already exercised at spawn. An untextured polygon
	# introduces a new GLES3 shader variant when the distant goal enters view.
	var goal_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	goal_image.fill(GOAL_COLOR)
	var goal_texture := ImageTexture.create_from_image(goal_image)
	var goal_art := Dressing.object_art(manifest, pack, "o5")
	for goal: Array in world.goals:
		var marker := Sprite2D.new()
		marker.texture = goal_texture if goal_art.is_empty() else goal_art.texture
		if not goal_art.is_empty():
			marker.centered = false
			marker.set_meta("pack_art", goal_art)
		marker.z_index = 10
		marker.set_meta("goal", true)
		marker.position = Vector2(goal[0], goal[1]) / State.SCALE
		_root.add_child(marker)
	# Recovery first appears mid-run; share the same generated texture and warmed shader.
	var recovery_art := Dressing.object_art(manifest, pack, "recovery")
	_recovery_marker.texture = (goal_texture if recovery_art.is_empty() else recovery_art.texture)
	if not recovery_art.is_empty():
		_recovery_marker.centered = false
		_recovery_marker.set_meta("pack_art", recovery_art)
	_recovery_marker.z_index = 12
	_recovery_marker.set_meta("recovery", true)
	_root.add_child(_recovery_marker)
	var background := str(world.bgcolor).split(",")
	if background.size() == 3:
		var channels := []
		for channel: String in background:
			if not channel.is_valid_float() or not is_finite(float(channel)):
				channels.clear()
				break
			channels.append(clampf(float(channel) / 255.0, 0, 1))
		if channels.size() == 3:
			RenderingServer.set_default_clear_color(Color(channels[0], channels[1], channels[2]))
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
	_background.render(plan, state.frame)
	for child: Node in _root.get_children():
		if child is Sprite2D and child != _player and not child.get_meta("stateful", false):
			Frames.apply(child, state.frame)
	_player.position = Vector2(state.x, state.y) / State.SCALE
	for index in _spring_nodes.size():
		var ball: Dictionary = state.springs[index]
		var node := _spring_nodes[index]
		var size := 48.0 if _world.springs[index].large else 32.0
		var squash: int = mini(ball.squash, 12 - ball.squash)
		node.position = Vector2(ball.x, ball.y) / State.SCALE
		node.visible = bool(ball.active)
		node.scale = (
			Vector2((size + 16.0 * squash / 6) / size, (size - 16.0 * squash / 6) / size)
			* float(node.get_meta("base"))
		)
	for index in _enemy_nodes.size():
		var enemy: Dictionary = state.enemies[index]
		var code: String = _world.enemies[index].code
		var bounds := Motion.box(enemy, code)
		var node := _enemy_nodes[index]
		Frames.apply(node, state.frame, enemy_pose(enemy, code))
		place_actor(node, enemy, bounds)
		node.visible = enemy.status == 1
		var head := _head_nodes[index]
		head.visible = enemy.status == 1 and code == "e5" and enemy.mode != 0
		if head.visible:
			Frames.apply(head, state.frame, "chew" if enemy.mode == 4 else "active")
			if head.get_meta("position_anchor", false):
				head.position = (
					Vector2(enemy.x, enemy.y) / State.SCALE + Vector2(enemy.facing * 2, -10)
				)
				head.rotation = Vector2(enemy.head_dx, enemy.head_dy).angle()
				head.flip_v = enemy.facing > 0
				head.scale = (
					Vector2(16 + 48 * enemy.head_size / 15.0, 16 + 38 * enemy.head_size / 15.0)
					/ Vector2(64, 54)
				)
			else:
				place_actor(head, enemy, Plant.head_box(enemy), false)
	_player.visible = (
		not state.captured_by and (not state.invulnerable or (120 - state.invulnerable) % 6 < 3)
	)
	_player.modulate.a = 0.5 if state.invulnerable else 1.0
	_recovery_marker.position = Vector2(state.recovery_x, state.recovery_y) / State.SCALE
	_recovery_marker.visible = state.separated and not state.recovery_delay
	if not _animations.is_empty():
		var pose := PlayerPose.select(state)
		_player.set_meta("pack_variant", pose.frame)
		Frames.apply(_player, pose.tick, pose.name)
		_player.scale.x = state.facing
	_goal_label.visible = bool(state.goal_reached or state.separated)
	_goal_label.text = "Goal" if state.goal_reached else "Recover: %d" % state.health
	_goal_label.position = Vector2(8, 8)


func actor_node(art: Dictionary, fallback: Texture2D) -> Sprite2D:
	var node: Sprite2D
	if art.is_empty():
		node = Sprite2D.new()
		node.texture = fallback
		node.centered = false
		node.z_index = 10
	else:
		node = Dressing.sprite(art, 10)
		node.set_meta("bottom", Dressing.bottom_anchored(art))
		node.set_meta("position_anchor", art.get("anchor", "box") == "position")
		node.set_meta("art_facing", art.get("facing", 1))
	node.set_meta("stateful", true)
	_root.add_child(node)
	return node


static func place_actor(node: Sprite2D, enemy: Dictionary, bounds: Array, relative := true) -> void:
	# Diagnostic textures stretch to the hitbox; pack art keeps its size and faces the motion.
	var x := float(enemy.x if relative else 0)
	var y := float(enemy.y if relative else 0)
	if not node.has_meta("bottom"):
		node.position = Vector2(x + bounds[0], y + bounds[1]) / State.SCALE
		node.scale = Vector2(bounds[2] - bounds[0], bounds[3] - bounds[1]) / (32 * State.SCALE)
		return
	if node.get_meta("position_anchor", false):
		node.position = Vector2(x, y) / State.SCALE
		node.scale.x = 1 if int(enemy.get("facing", 1)) == node.get_meta("art_facing", 1) else -1
		return
	var anchor_y: float = (
		float(bounds[3]) if node.get_meta("bottom") else (bounds[1] + bounds[3]) / 2.0
	)
	node.position = Vector2(x + (bounds[0] + bounds[2]) / 2.0, y + anchor_y) / State.SCALE
	node.flip_h = int(enemy.get("facing", 1)) < 0


static func enemy_pose(enemy: Dictionary, code: String) -> String:
	if code == "e2":
		return "fly"
	if code == "e3" and enemy.mode:
		return "turn"
	if code == "e5":
		return "active" if enemy.mode else "idle"
	if code == "e20":
		if enemy.mode == 2:
			return "prepare"
		if enemy.water and enemy.mode != 3:
			return "swim"
		return "jump" if enemy.vy < 0 else "fall"
	return "walk" if enemy.vx else "idle"


static func draw_before(a: Dictionary, b: Dictionary) -> bool:
	return a.slot[0] < b.slot[0] or (a.slot[0] == b.slot[0] and a.slot[1] < b.slot[1])


static func load_texture(path: String) -> Texture2D:
	return Dressing.load_texture(path)


static func placeholder(name: String, size: int) -> Texture2D:
	# Stable per-tileset colors. These are diagnostic flat squares, not art.
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.from_hsv(float(absi(name.hash()) % 360) / 360.0, 0.55, 0.65))
	return ImageTexture.create_from_image(image)
