class_name PlayState
extends RefCounted
## Flat scalar state plus one ordered entity table. All schema values are int64.

const Moves = preload("res://src/sim/moves.gd")
const Life = preload("res://src/sim/life.gd")
const Maps = preload("res://src/sim/maps.gd")
const Units = preload("res://src/sim/units.gd")
const SCALE := Units.SCALE
const BASE_LEVEL_FIELDS := [
	["frame", 0], ["camera_x", 0], ["camera_y", 0],
	["goal_reached", 0], ["deaths", 0], ["rng", 1]
]
const BASE_PLAYER_FIELDS := [
	["x", 0], ["y", 0], ["vx", 0], ["vy", 0], ["movement", 0],
	["facing", 1], ["on_floor", 0], ["previous_input", 0], ["pressed_input", 0],
	["jump_buffer", 0], ["flutter_remaining", 0], ["flutter_cooldown", 0],
	["flutter_ready", 0], ["support_bridge", 0], ["swimming", 0],
	["water_wait", 0], ["water_phase", 0], ["water_deep", 0],
	["boosted_flutter", 0], ["captured_by", 0]
]


static func compose(lists: Array) -> Array:
	# Owners can extend an existing field without encoding the same scalar twice.
	# First occurrence fixes position; the last declaration supplies its default.
	var result := []
	var positions := {}
	for list: Array in lists:
		for pair: Array in list:
			assert(pair.size() == 2 and pair[0] is String and pair[1] is int)
			if positions.has(pair[0]):
				result[positions[pair[0]]] = pair.duplicate()
			else:
				positions[pair[0]] = result.size()
				result.append(pair.duplicate())
	return result


static func player_fields() -> Array:
	return compose([BASE_PLAYER_FIELDS, Moves.PLAYER_FIELDS, Life.PLAYER_FIELDS])


static func level_fields() -> Array:
	return compose([BASE_LEVEL_FIELDS, Life.LEVEL_FIELDS, Maps.LEVEL_FIELDS])


static func fields() -> Array:
	var level := level_fields()
	var player := player_fields()
	for pair: Array in player:
		for other: Array in level:
			assert(pair[0] != other[0], "Field belongs to both player and level")
	level.append_array(player)
	return level


static func create(world: Dictionary) -> Dictionary:
	var state := {"identity": world.identity}
	for pair: Array in fields():
		state[pair[0]] = pair[1]
	# Level schema values can be supplied by the compiled world, including map index.
	for pair: Array in level_fields():
		state[pair[0]] = int(world.get(pair[0], pair[1]))
	state.x = int(world.spawn_x)
	state.y = int(world.spawn_y)
	state.facing = int(world.get("spawn_facing", state.facing))
	state.camera_x = state.x
	state.camera_y = state.y - 28 * SCALE
	var registry: Script = load("res://src/sim/registry.gd")
	registry.spawn_map(state, world)
	return state


static func input_mask() -> int:
	var module: Script = Moves
	return int(module.get_script_constant_map().get("INPUT_MASK", 15))


static func valid(state: Dictionary) -> bool:
	var declared := {"identity": true, "entities": true, "enemies": true, "springs": true}
	for pair: Array in fields():
		declared[pair[0]] = true
		if not state.get(pair[0]) is int:
			return false
	for key: Variant in state:
		if not declared.has(key):
			return false
	if (
		state.frame < 0 or state.deaths < 0
		or state.facing not in [-1, 1] or state.on_floor not in [0, 1]
		or state.goal_reached not in [0, 1]
		or state.previous_input < 0 or state.previous_input & ~input_mask() != 0
		or state.pressed_input < 0 or state.pressed_input & ~input_mask() != 0
		or state.captured_by < 0 or state.rng < 0 or state.rng > 0x7fffffff
	):
		return false
	for module: Script in [Moves, Life, Maps]:
		if module.has_method("valid_state") and not module.valid_state(state):
			return false
	return true
