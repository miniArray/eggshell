extends RefCounted
## Saved map selection and level-wide goals. Compiled maps are immutable caches.

const S := preload("res://src/sim/units.gd").SCALE
const LEVEL_FIELDS := [
	["map_index", 1],
	["map_count", 1],
	["flowers_target", 0],
	["redcoins_target", 0],
]


static func select_map(world: Dictionary, map_index: int) -> bool:
	if not world.get("maps", {}).has(map_index):
		return false
	world.merge(world.maps[map_index], true)
	return true


static func map_world(world: Dictionary, map_index: int) -> Dictionary:
	if not world.get("maps", {}).has(map_index):
		return {}
	var selected := world.duplicate()
	select_map(selected, map_index)
	return selected


static func initialize(state: Dictionary, world: Dictionary) -> void:
	state.map_index = int(world.initial_map)
	state.map_count = int(world.map_count)
	state.flowers_target = int(world.flowers_target)
	state.redcoins_target = int(world.redcoins_target)
	state.facing = int(world.spawn_facing)


static func valid_state(state: Dictionary) -> bool:
	for entry: Array in LEVEL_FIELDS:
		if not state.get(entry[0]) is int:
			return false
	return (
		state.map_count > 0
		and state.map_count <= 0x7fffffff
		and state.map_index > 0
		and state.map_index <= state.map_count
		and state.flowers_target >= 0
		and state.flowers_target <= 0x7fffffff
		and state.redcoins_target >= 0
		and state.redcoins_target <= 0x7fffffff
	)


static func sync(state: Dictionary, world: Dictionary) -> bool:
	# Initialize older callers at their first step; schema-aware creation calls this explicitly.
	if not state.has("map_index"):
		initialize(state, world)
	if not valid_state(state) or state.map_count != world.map_count:
		return false
	if (
		state.flowers_target != world.flowers_target
		or state.redcoins_target != world.redcoins_target
	):
		return false
	return select_map(world, int(state.map_index))


static func change(
	state: Dictionary,
	world: Dictionary,
	map_index: int,
	target_x: int,
	target_y: int,
	reset_map: Callable
) -> bool:
	var selected := map_world(world, map_index)
	if selected.is_empty() or not valid_state(state) or not sync(state, world):
		return false
	if target_x < 0 or target_y < 0 or target_x > selected.width or target_y > selected.height:
		return false
	# The caller supplies Registry.spawn_map. Never retain it as play state.
	if not reset_map.is_valid():
		return false
	state.map_index = map_index
	select_map(world, map_index)
	reset_map.call(state, world)
	state.x = target_x
	state.y = target_y
	for field: String in ["vx", "vy", "movement", "on_floor", "support_bridge", "captured_by"]:
		state[field] = 0
	state.camera_x = target_x
	state.camera_y = target_y - 28 * S
	return true


static func index_for(world: Dictionary, source_map_number: int) -> int:
	for index: int in world.maps:
		if world.maps[index].map_name == "map%d" % source_map_number:
			return index
	return 0
