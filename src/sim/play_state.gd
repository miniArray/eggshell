class_name PlayState
extends RefCounted
## Flat scalar state plus one ordered entity table. All schema values are int64.

const Moves = preload("res://src/sim/moves.gd")
const Life = preload("res://src/sim/life.gd")
const Maps = preload("res://src/sim/maps.gd")
const Sound = preload("res://src/sim/sound_events.gd")
const Units = preload("res://src/sim/units.gd")
const SCALE := Units.SCALE
const BASE_LEVEL_FIELDS := [
	["frame", 0], ["camera_x", 0], ["camera_y", 0], ["goal_reached", 0], ["deaths", 0], ["rng", 1]
]
const BASE_PLAYER_FIELDS := [
	["x", 0],
	["y", 0],
	["vx", 0],
	["vy", 0],
	["movement", 0],
	["facing", 1],
	["on_floor", 0],
	["previous_input", 0],
	["pressed_input", 0],
	["jump_buffer", 0],
	["flutter_remaining", 0],
	["flutter_cooldown", 0],
	["flutter_ready", 0],
	["support_bridge", 0],
	["swimming", 0],
	["water_wait", 0],
	["water_phase", 0],
	["water_deep", 0],
	["boosted_flutter", 0],
	["captured_by", 0]
]
# Schemas are constant for a run. Snapshots read them on every autosave, so each one is
# composed once and shared read-only. Copy a schema before changing it.
static var _player_fields: Array = []
static var _level_fields: Array = []
static var _fields: Array = []


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


static func freeze(schema: Array) -> Array:
	for pair: Array in schema:
		pair.make_read_only()
	schema.make_read_only()
	return schema


static func player_fields() -> Array:
	if _player_fields.is_empty():
		_player_fields = freeze(
			compose([BASE_PLAYER_FIELDS, Moves.PLAYER_FIELDS, Life.PLAYER_FIELDS])
		)
	return _player_fields


static func entity_registry() -> Script:
	return load("res://src/sim/registry.gd")


static func level_fields() -> Array:
	if _level_fields.is_empty():
		_level_fields = freeze(compose_level_fields())
	return _level_fields


static func compose_level_fields() -> Array:
	var registry := entity_registry()
	var result := compose(
		[BASE_LEVEL_FIELDS, Life.LEVEL_FIELDS, Maps.LEVEL_FIELDS, Sound.LEVEL_FIELDS]
	)
	for pair: Array in registry.level_fields():
		assert(
			not result.any(func(core: Array) -> bool: return core[0] == pair[0]),
			"Entity level field overlaps core state: " + pair[0]
		)
		result.append(pair)
	return result


static func fields() -> Array:
	if _fields.is_empty():
		var level := level_fields()
		var player := player_fields()
		for pair: Array in player:
			for other: Array in level:
				assert(pair[0] != other[0], "Field belongs to both player and level")
		var result := []
		for pair: Array in level + player:
			result.append(pair.duplicate())
		_fields = freeze(result)
	return _fields


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
	Maps.initialize(state, world)
	Life.initialize(state, world)
	var registry := entity_registry()
	registry.spawn_map(state, world)
	# The state starts at the first step that reads input, after the level-start ticks.
	var simulation: Script = load("res://src/sim/step.gd")
	simulation.begin_level(state, world)
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
		state.frame < 0
		or state.deaths < 0
		or state.facing not in [-1, 1]
		or state.on_floor not in [0, 1]
		or state.goal_reached not in [0, 1]
		or state.previous_input < 0
		or state.previous_input & ~input_mask() != 0
		or state.pressed_input < 0
		or state.pressed_input & ~input_mask() != 0
		or state.captured_by < 0
		or state.rng < 0
		or state.rng > 0x7fffffff
	):
		return false
	for limit: Array in [
		["movement", 0, 6],
		["jump_buffer", 0, 6],
		["flutter_remaining", 0, 72],
		["flutter_cooldown", 0, 17],
		["water_wait", 0, 15],
		["water_phase", 0, 59]
	]:
		if state[limit[0]] < limit[1] or state[limit[0]] > limit[2]:
			return false
	for flag: String in ["flutter_ready", "swimming", "water_deep", "boosted_flutter"]:
		if state[flag] not in [0, 1]:
			return false
	if state.support_bridge < 0:
		return false
	for module: Script in [Moves, Life, Maps, Sound]:
		if module.has_method("valid_state") and not module.valid_state(state):
			return false
	return entity_registry().valid_state(state)
