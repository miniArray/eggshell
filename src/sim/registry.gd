extends RefCounted
## Object dispatch and ordered int64 schemas. Placement options stay in the world.

const Actor = preload("res://src/sim/types/actor.gd")
const Pad = preload("res://src/sim/types/pad.gd")
const Bridge = preload("res://src/sim/types/bridge.gd")
const Goal = preload("res://src/sim/types/goal.gd")
const Checkpoint = preload("res://src/sim/types/checkpoint.gd")
const Inert = preload("res://src/sim/types/inert.gd")
const TYPES := [
	Actor,
	Pad,
	Bridge,
	Goal,
	Checkpoint,
	# slice 6: s6-decor
	preload("res://src/sim/types/decor.gd"),
	preload("res://src/sim/types/decor_platform.gd"),
	preload("res://src/sim/types/lamp.gd"),
	preload("res://src/sim/types/snow_tree.gd")
]
const Units = preload("res://src/sim/units.gd")
const S := Units.SCALE
const MAX_OPTION_PIXELS := 0x7fffffffffffffff / S - 1
const WAITING := 0
const ACTIVE := 1
const QUEUED := 2
const DEFEATED := 3
const COMMON_FIELDS := [
	["source_index", 0],
	["map_index", 0],
	["family_index", 0],
	["collected", 0],
	["checkpoint_collected", 0],
	["x", 0],
	["y", 0],
	["vx", 0],
	["vy", 0],
	["facing", -1],
	["layer", 7],
	["status", WAITING],
	["offscreen", 0],
	["spawn_mode", 0],
	["can_despawn", 0],
	["can_respawn", 0],
	["activation_x", 416 * S],
	["activation_y", 224 * S],
	["despawn_radius", 832 * S],
	["respawn_radius", 624 * S]
]


static func lookup(code: String) -> Script:
	for type: Script in TYPES:
		if code in type.CODES:
			return type
	return Inert


static func implemented(code: String) -> bool:
	return lookup(code) != Inert


static func fields(code: String) -> Array:
	var result := COMMON_FIELDS.duplicate(true)
	result.append_array(lookup(code).FIELDS.duplicate(true))
	return result


static func codes() -> Array[String]:
	var result: Array[String] = []
	for type: Script in TYPES:
		for code: String in type.CODES:
			assert(not result.has(code), "Duplicate object code")
			result.append(code)
	return result


static func compile_map(objects: Dictionary, world: Dictionary) -> Dictionary:
	world.entities = []
	world.enemies = []
	world.springs = []
	world.bridges = []
	world.goals = []
	for source_id: Variant in objects:
		var raw_value: Variant = objects[source_id]
		if (
			not source_id is String
			or not raw_value is Dictionary
			or not raw_value.get("A") is String
		):
			return {"ok": false, "error": "Invalid object record or code"}
		var raw: Dictionary = raw_value
		for key: String in ["X", "Y"]:
			if not finite_number(raw.get(key)) or not numeric_option(raw[key]).ok:
				return {"ok": false, "error": "Invalid object position: " + key}
		var code: String = raw.A
		var source := {
			"source_index": world.entities.size(),
			"id": source_id,
			"code": code,
			"properties": raw.duplicate(true),
			"x": roundi(raw.X * S),
			"y": roundi(raw.Y * S),
			"variant": 0,
			"mirror": 0,
			"rotation": 0,
			"layer": 8 if code in Actor.CODES else 7,
			"family_index": 0
		}
		for option: Array in [["F", "variant"], ["M", "mirror"], ["R", "rotation"]]:
			var value: Variant = raw.get(option[0], 0)
			if (
				finite_number(value)
				and value == floor(value)
				and value >= -MAX_OPTION_PIXELS
				and value <= MAX_OPTION_PIXELS
			):
				source[option[1]] = int(value)
		if code in Actor.CODES:
			for key: String in ["F", "M", "R"]:
				var value: Variant = raw.get(key, 0)
				if (
					not finite_number(value)
					or value != floor(value)
					or value < 0
					or value > MAX_OPTION_PIXELS
				):
					return {"ok": false, "error": "Invalid actor field: " + key}
			source.variant = int(raw.get("F", 0))
			source.mirror = int(raw.get("M", 0))
			source.rotation = int(raw.get("R", 0))
			if source.rotation != 0 or source.mirror > 2 or source.variant > 4:
				return {"ok": false, "error": "Unsupported actor variant, mirror or rotation"}
			if code in ["e3", "e5"] and source.variant != 0:
				return {"ok": false, "error": "Unsupported rooted or tumbler variant"}
			if code == "e20" and source.variant not in [0, 1]:
				return {"ok": false, "error": "Unsupported fish mode"}
			source.family_index = world.enemies.size()
			world.enemies.append(source)
		elif code == "o11":
			var value: Variant = raw.get("F", 0)
			if (
				not finite_number(value)
				or value != floor(value)
				or value < 0
				or value > MAX_OPTION_PIXELS
			):
				return {"ok": false, "error": "Invalid pad variant"}
			source.variant = int(value)
			source.y += 16 * S
			source.large = source.variant % 2
			source.single_use = int(source.variant >= 2)
			source.family_index = world.springs.size()
			world.springs.append(source)
		elif code == "p1":
			var width := numeric_option(raw.get("E1"))
			if not width.ok or width.value < 0:
				return {"ok": false, "error": "Invalid bridge width"}
			var size := roundi(width.value * S)
			source.left = source.x - size / 2
			source.right = source.x + size / 2
			source.top = source.y - 16 * S
			world.bridges.append(source)
		elif code == "o5":
			world.goals.append([source.x, source.y])
		elif code == "o6":
			for key: String in ["E1", "E2"]:
				var parsed := numeric_option(raw.get(key))
				if not parsed.ok:
					return {"ok": false, "error": "Invalid checkpoint position: " + key}
				source["respawn_x" if key == "E1" else "respawn_y"] = roundi(parsed.value * S)
		var type := lookup(code)
		if type.has_method("prepare"):
			var prepared: Dictionary = type.prepare(source, world)
			if not prepared.get("ok", false):
				return {
					"ok": false, "error": str(prepared.get("error", "Invalid placement options"))
				}
		world.entities.append(source)
	return {"ok": true}


static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)


static func numeric_option(value: Variant) -> Dictionary:
	if value is String:
		var text: String = value.strip_edges()
		if not text.is_valid_float():
			return {"ok": false}
		value = text.to_float()
	if not finite_number(value) or value < -MAX_OPTION_PIXELS or value > MAX_OPTION_PIXELS:
		return {"ok": false}
	return {"ok": true, "value": float(value)}


static func create(source: Dictionary, world: Dictionary) -> Dictionary:
	var type := lookup(source.code)
	var entity := {"code": source.code, "id": source.id}
	for pair: Array in fields(source.code):
		assert(pair.size() == 2 and pair[0] is String and pair[1] is int)
		assert(not entity.has(pair[0]), "Duplicate entity field")
		entity[pair[0]] = pair[1]
	for key: String in ["source_index", "x", "y", "layer", "family_index"]:
		entity[key] = int(source.get(key, entity[key]))
	entity.map_index = int(world.get("map_index", 0))
	entity.facing = 1 if source.get("mirror", 0) == 1 else -1
	entity.status = ACTIVE
	var values: Dictionary = type.create(source, world)
	for key: String in values:
		assert(entity.has(key) and values[key] is int, "Undeclared type state")
		entity[key] = values[key]
	if entity.spawn_mode == 1 and not values.has("status"):
		entity.status = WAITING
	return entity


static func spawn_map(state: Dictionary, world: Dictionary, keep_flags: bool = false) -> void:
	var previous := {}
	if keep_flags:
		for entity: Dictionary in state.get("entities", []):
			if entity.map_index == world.get("map_index", 0):
				previous[entity.id] = entity.checkpoint_collected
	state.entities = []
	for source: Dictionary in world.get("entities", []):
		var entity := create(source, world)
		if previous.has(entity.id):
			entity.collected = previous[entity.id]
			entity.checkpoint_collected = previous[entity.id]
		state.entities.append(entity)
	attach_views(state)


static func attach_views(state: Dictionary) -> void:
	# Transitional read views share dictionaries; they are not separate saved state.
	state.enemies = []
	state.springs = []
	for entity: Dictionary in state.entities:
		if entity.code in Actor.CODES:
			state.enemies.append(entity)
		elif entity.code == "o11":
			state.springs.append(entity)


static func source_for(entity: Dictionary, world: Dictionary) -> Dictionary:
	return world.entities[entity.source_index]


static func phase_for(type: Script, key: String, fallback: int) -> int:
	return int(type.get_script_constant_map().get(key, fallback))


static func advance(state: Dictionary, world: Dictionary, pressed: int) -> void:
	state.pressed_input = pressed
	# Preserve actor movement before pad gravity, including capture's early exit.
	for phase in [0, 1]:
		if phase == 1 and state.captured_by:
			break
		for entity: Dictionary in state.entities:
			var type := lookup(entity.code)
			if phase_for(type, "STEP_PHASE", 0) != phase:
				continue
			lifecycle(entity, state, world)
			if entity.status == ACTIVE:
				type.step(entity, state, world)


static func lifecycle(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status == DEFEATED:
		return
	var source := source_for(entity, world)
	if entity.status == ACTIVE and entity.can_despawn:
		if (
			absi(entity.x - state.camera_x) > entity.despawn_radius
			or absi(entity.y - state.camera_y) > entity.despawn_radius
		):
			entity.status = QUEUED
			entity.offscreen = 0
	if entity.status == QUEUED and entity.can_respawn:
		if (
			absi(source.x - state.camera_x) > entity.activation_x
			or absi(source.y - state.camera_y) > entity.activation_y
		):
			entity.offscreen = 1
		if (
			entity.offscreen
			and absi(source.x - state.camera_x) < entity.respawn_radius
			and absi(source.y - state.camera_y) < entity.respawn_radius
		):
			var fresh := create(source, world)
			fresh.collected = entity.collected
			fresh.checkpoint_collected = entity.checkpoint_collected
			for pair: Array in fields(entity.code):
				entity[pair[0]] = fresh[pair[0]]
	if entity.status == WAITING:
		var type := lookup(entity.code)
		var bounds: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
		if (
			entity.x + bounds[2] > state.camera_x - entity.activation_x
			and entity.x + bounds[0] < state.camera_x + entity.activation_x
			and entity.y + bounds[3] > state.camera_y - entity.activation_y
			and entity.y + bounds[1] < state.camera_y + entity.activation_y
		):
			entity.status = ACTIVE
			if source.mirror == 2:
				entity.facing = -1 if state.x < entity.x else 1
			if type.has_method("activate"):
				type.activate(entity, state, world)


static func contact(state: Dictionary, input: int, world: Dictionary) -> void:
	for phase in [0, 1, 2]:
		for entity: Dictionary in state.entities:
			var type := lookup(entity.code)
			if (
				type.has_method("contact")
				and phase_for(type, "CONTACT_PHASE", 1) == phase
				and entity.status == ACTIVE
			):
				type.contact(entity, state, world, input)


static func goal_convert(state: Dictionary, _world: Dictionary, on_coin: Callable) -> void:
	if not on_coin.is_valid():
		return
	for entity: Dictionary in state.entities:
		var type := lookup(entity.code)
		if entity.status != ACTIVE or not type.get_script_constant_map().get("GOAL_COIN", false):
			continue
		var bounds: Array = type.bounds(entity)
		if (
			entity.x + bounds[2] > state.camera_x - 416 * S
			and entity.x + bounds[0] < state.camera_x + 416 * S
			and entity.y + bounds[3] > state.camera_y - 224 * S
			and entity.y + bounds[1] < state.camera_y + 224 * S
		):
			entity.status = DEFEATED
			on_coin.call(state)


static func valid(entity: Dictionary) -> bool:
	if not entity.get("code") is String or not entity.get("id") is String:
		return false
	var schema := fields(entity.code)
	if entity.size() != schema.size() + 2:
		return false
	for pair: Array in schema:
		if not entity.get(pair[0]) is int:
			return false
	for key: String in [
		"collected", "checkpoint_collected", "offscreen", "spawn_mode", "can_despawn", "can_respawn"
	]:
		if entity[key] not in [0, 1]:
			return false
	for key: String in [
		"source_index",
		"map_index",
		"family_index",
		"activation_x",
		"activation_y",
		"despawn_radius",
		"respawn_radius"
	]:
		if entity[key] < 0:
			return false
	if entity.facing not in [-1, 1] or entity.status not in [WAITING, ACTIVE, QUEUED, DEFEATED]:
		return false
	return lookup(entity.code).valid(entity)


static func valid_world(state: Dictionary, world: Dictionary) -> bool:
	if state.entities.size() != world.get("entities", []).size():
		return false
	for index in state.entities.size():
		if (
			state.entities[index].source_index != index
			or state.entities[index].id != world.entities[index].id
			or state.entities[index].code != world.entities[index].code
		):
			return false
	return true
