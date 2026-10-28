extends Node2D
## Map presentation only. All timing comes from the saved simulation tick.

const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const PLAYER_KEYS := [[0, 248, 0], [0, 168, 0], [0, 96, 0]]
const SHIMMER_STEPS := [
	[[0, 0]],
	[[1, 1]],
	[[2, 2], [3, 3]],
	[[4, 4], [5, 5], [6, 6]],
	[[7, 7], [8, 8]],
	[[10, 10], [11, 12]]
]
# Tone keys and replacements for the five supported 64-pixel cave styles.
const SHIMMER_FROM := [
	(
		"240,248,184-128,184,152-112,136,168-128,184,152-128,112,104-"
		+ "112,136,168-128,184,152-128,112,104-112,136,168-128,184,152-"
		+ "128,112,104-112,136,168-128,112,104"
	),
	(
		"248,248,248-156,231,255-115,198,222-156,231,255-90,156,181-"
		+ "115,198,222-156,231,255-90,156,181-115,198,222-156,231,255-"
		+ "90,156,181-115,198,222-90,156,181"
	),
	(
		"255,198,123-239,156,123-189,123,82-239,156,123-115,107,82-"
		+ "189,123,82-255,198,123-115,107,82-189,123,82-255,198,123-"
		+ "115,107,82-189,123,82-115,107,82"
	),
	(
		"248,248,192-224,200,144-160,112,88-224,200,144-104,64,32-"
		+ "160,112,88-224,200,144-104,64,32-160,112,88-224,200,144-"
		+ "104,64,32-160,112,88-224,200,144"
	),
	(
		"200,176,152-144,128,104-96,88,72-144,128,104-24,16,8-"
		+ "96,88,72-144,128,104-24,16,8-96,88,72-144,128,104-"
		+ "24,16,8-96,88,72-144,128,104"
	),
]
const SHIMMER_TO := [
	(
		"248,248,248-248,248,248-208,232,248-176,232,200-240,224,216-"
		+ "160,184,216-152,208,176-176,160,152-136,160,192-128,184,152-"
		+ "152,136,128-112,136,168-128,112,104"
	),
	(
		"224,248,248-184,248,248-144,240,248-240,248,248-120,200,208-"
		+ "232,248,248-216,248,248-200,248,248-176,248,248-168,240,248-"
		+ "152,232,240-128,208,232-104,168,192"
	),
	(
		"248,248,248-248,248,248-208,232,248-248,192,120-240,224,216-"
		+ "232,152,120-248,192,120-176,160,152-184,120,80-248,192,120-"
		+ "152,136,128-184,120,80-128,112,104"
	),
	(
		"248,248,248-248,248,248-255,255,209-255,246,225-207,188,173-"
		+ "203,156,133-242,226,187-151,116,88-186,136,111-224,200,144-"
		+ "125,87,57-160,112,88-224,200,144"
	),
	(
		"248,248,248-248,248,248-186,182,170-216,206,190-112,99,86-"
		+ "156,150,137-182,167,145-91,74,56-130,123,108-144,128,104-"
		+ "61,44,28-96,88,72-144,128,104"
	),
]
const SWAP_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec3 keys[3];
uniform vec3 values[3];
uniform int count = 0;
varying vec4 vertex_colour;
void vertex() { vertex_colour = COLOR; }
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	for (int i = 0; i < 3; i++) {
		if (i < count && all(lessThan(abs(pixel.rgb - keys[i]), vec3(0.5 / 255.0)))) {
			pixel.rgb = values[i];
		}
	}
	COLOR = pixel * vertex_colour;
}
"""
const DARK_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 viewport_size;
uniform vec2 light_origin;
uniform float light_radius = 128.0;
uniform float strength = 0.0;
void fragment() {
	float distance_from_light = distance(SCREEN_UV * viewport_size, light_origin);
	float shade = smoothstep(0.0, max(light_radius, 0.001), distance_from_light);
	COLOR = vec4(0.0, 0.0, 0.0, strength * shade);
}
"""
var _base := ColorRect.new()
var _dark := ColorRect.new()
var _tint := ColorRect.new()
var _shade := ShaderMaterial.new()
var _swap := Shader.new()
var _prepared_root := 0
var _shimmer_nodes: Array[Dictionary] = []


func _init() -> void:
	var darkness := Shader.new()
	darkness.code = DARK_SHADER
	_shade.shader = darkness
	_swap.code = SWAP_SHADER
	for node: ColorRect in [_base, _dark, _tint]:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(node)
	_base.z_index = -40
	_dark.z_index = 20
	_tint.z_index = 21
	_dark.material = _shade


func update(
	root: Node2D,
	player: Sprite2D,
	world: Dictionary,
	state: Dictionary,
	view_plan: Dictionary,
	viewport: Vector2
) -> void:
	if _prepared_root != root.get_instance_id():
		_prepare(root, player, world)
	var policy := plan(world, state, view_plan, viewport)
	for node: ColorRect in [_base, _dark, _tint]:
		node.size = viewport
	_base.color = policy.background
	_tint.color = policy.tint
	_tint.visible = policy.tint.a > 0
	_dark.visible = policy.darkness > 0
	_shade.set_shader_parameter("viewport_size", viewport)
	_shade.set_shader_parameter("light_origin", policy.light_origin)
	_shade.set_shader_parameter("light_radius", policy.light_radius)
	_shade.set_shader_parameter("strength", policy.darkness)
	for entry: Dictionary in _shimmer_nodes:
		var pairs := shimmer_swaps(entry.name, int(state.frame))
		_set_swaps(entry.node, pairs)


func _prepare(root: Node2D, player: Sprite2D, world: Dictionary) -> void:
	_prepared_root = root.get_instance_id()
	_shimmer_nodes.clear()
	var palette: Array = world.get("player_palette", [])
	if not palette.is_empty():
		var pairs := []
		for index in 3:
			pairs.append(
				[PLAYER_KEYS[index], palette[index] if index < palette.size() else [0, 0, 0]]
			)
		_set_swaps(player, pairs)
	for node: Node in root.get_children():
		if node is TileMapLayer and world.get("cave_shimmer", 0):
			var name: String = node.get_meta("tilemap_name", "")
			if _cave_variant(name) >= 0:
				_shimmer_nodes.append({"node": node, "name": name})
		if node is Sprite2D and node.get_meta("placed_code", "") in ["o33", "o34"]:
			var source: Dictionary = node.get_meta("placed_source", {})
			node.self_modulate = _colour(dice_colour(world, source))


func _set_swaps(node: CanvasItem, pairs: Array) -> void:
	var material: ShaderMaterial = (
		node.get_meta("map_swaps") if node.has_meta("map_swaps") else null
	)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = _swap
		node.material = material
		node.set_meta("map_swaps", material)
	var keys := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var values := keys.duplicate()
	for index in mini(3, pairs.size()):
		keys[index] = _vector(pairs[index][0])
		values[index] = _vector(pairs[index][1])
	material.set_shader_parameter("keys", keys)
	material.set_shader_parameter("values", values)
	material.set_shader_parameter("count", mini(3, pairs.size()))


static func plan(
	world: Dictionary, state: Dictionary, view_plan: Dictionary, _viewport: Vector2
) -> Dictionary:
	var tint := str(world.get("tint", "0_255,255,255")).split("_")
	var tint_strength := clampf(tint[0].to_float(), 0.0, 50.0)
	if tint_strength < 1.0 or not is_finite(tint_strength):
		tint_strength = 0.0
	var tint_colour := _colour(World.rgb(tint[1] if tint.size() > 1 else "0,0,0"))
	tint_colour.a = tint_strength / 100.0
	var center := Vector2(int(state.x), int(state.y) - 28 * S) / S
	return {
		"background": _colour(World.rgb(str(world.get("bgcolor", "132,222,255")))),
		"darkness": clampf(float(world.get("darkness", 0)), 0.0, 100.0) / 100.0,
		"tint": tint_colour,
		"light_origin": view_plan.offset + center * view_plan.scale,
		"light_radius": 128.0 * view_plan.scale,
	}


static func dice_colour(world: Dictionary, source: Dictionary) -> Array:
	var group := str(source.get("E4", "0")).to_int()
	var table: Array = world.get("dice_colours", [])
	if group >= 0 and group < table.size():
		return table[group]
	return World.rgb(
		"%s,%s,%s" % [source.get("E1", 255), source.get("E2", 255), source.get("E3", 255)]
	)


static func shimmer_swaps(name: String, frame: int) -> Array:
	var variant := _cave_variant(name)
	if variant < 0 or frame < 60 or frame % 60 >= 42:
		return []
	var phase: int = (frame % 60) / 6
	var from: PackedStringArray = SHIMMER_FROM[variant].split("-")
	var to: PackedStringArray = SHIMMER_TO[variant].split("-")
	if phase == 6:
		# The final step uses the shared end keys, rather than a new pulse.
		var end_from := (
			SHIMMER_FROM[0].split("-")[12]
			if variant == 0
			else SHIMMER_FROM[1].split("-")[0] if variant == 1 else "0,0,0"
		)
		var end_to := (
			SHIMMER_TO[0].split("-")[12]
			if variant == 0
			else SHIMMER_TO[1].split("-")[0] if variant == 1 else "0,0,0"
		)
		return [[World.rgb(end_from), World.rgb(end_to)]]
	var result := []
	for pair: Array in SHIMMER_STEPS[phase]:
		result.append([World.rgb(from[pair[0]]), World.rgb(to[pair[1]])])
	return result


static func _cave_variant(name: String) -> int:
	if name == "cave64":
		return 0
	var suffix := name.trim_prefix("cave64_")
	if name.begins_with("cave64_") and suffix.is_valid_int() and int(suffix) in range(1, 5):
		return int(suffix)
	return -1


static func _colour(channels: Array) -> Color:
	return Color(float(channels[0]) / 255.0, float(channels[1]) / 255.0, float(channels[2]) / 255.0)


static func _vector(channels: Array) -> Vector3:
	return Vector3(channels[0], channels[1], channels[2]) / 255.0
