extends RefCounted
## Object dispatch and ordered int64 schemas. Placement options stay in the world.

const Actor = preload("res://src/sim/types/actor.gd")
const Pad = preload("res://src/sim/types/pad.gd")
const Bridge = preload("res://src/sim/types/bridge.gd")
const Goal = preload("res://src/sim/types/goal.gd")
const Checkpoint = preload("res://src/sim/types/checkpoint.gd")
const Inert = preload("res://src/sim/types/inert.gd")
const PLACEHOLDER_PREFIX := "?"
const TYPES := [
	Actor,
	Pad,
	Bridge,
	Goal,
	Checkpoint,
	# slice 6: s6-items
	preload("res://src/sim/types/pickup.gd"),
	preload("res://src/sim/types/item_block.gd"),
	preload("res://src/sim/types/item_egg.gd"),
	preload("res://src/sim/types/item_star.gd"),
	preload("res://src/sim/types/item_stem.gd"),
	# slice 6: s6-enemies
	preload("res://src/sim/types/flat_walker.gd"),
	preload("res://src/sim/types/shell_walker.gd"),
	preload("res://src/sim/types/armored_walker.gd"),
	preload("res://src/sim/types/hanging_roller.gd"),
	preload("res://src/sim/types/masked_shooter.gd"),
	preload("res://src/sim/types/spitting_stem.gd"),
	preload("res://src/sim/types/enemy_spike.gd"),
	preload("res://src/sim/types/enemy_pellet.gd"),
	preload("res://src/sim/types/enemy_overlap.gd"),
	# slice 6: s6-platforms
	preload("res://src/sim/types/cloud_span.gd"),
	preload("res://src/sim/types/falling_span.gd"),
	preload("res://src/sim/types/hard_block.gd"),
	preload("res://src/sim/types/redirect_cloud.gd"),
	preload("res://src/sim/types/one_way_gate.gd"),
	preload("res://src/sim/types/pound_post.gd"),
	preload("res://src/sim/types/release_cloud.gd"),
	preload("res://src/sim/types/timed_switch.gd"),
	# slice 6: s6-decor
	preload("res://src/sim/types/decor.gd"),
	preload("res://src/sim/types/decor_platform.gd"),
	preload("res://src/sim/types/lamp.gd"),
	preload("res://src/sim/types/snow_tree.gd"),
	# slice 7: objects
	preload("res://src/sim/types/thorn_block.gd"),
	preload("res://src/sim/types/colour_block.gd"),
	preload("res://src/sim/types/grow_block.gd"),
	preload("res://src/sim/types/plank_bridge.gd"),
	preload("res://src/sim/types/bare_runner.gd"),
	preload("res://src/sim/types/spike_hopper.gd"),
	preload("res://src/sim/types/spine_walker.gd"),
	preload("res://src/sim/types/wing_drifter.gd"),
	preload("res://src/sim/types/petal_stem.gd"),
	preload("res://src/sim/types/stem_petal.gd"),
	preload("res://src/sim/types/needle_juggler.gd"),
	preload("res://src/sim/types/ride_hound.gd"),
	# slice 8: objects A
	preload("res://src/sim/types/ledge_span.gd"),
	preload("res://src/sim/types/count_ledge.gd"),
	preload("res://src/sim/types/star_flower.gd"),
	preload("res://src/sim/types/hang_flyer.gd"),
	preload("res://src/sim/types/sneak_thief.gd"),
	preload("res://src/sim/types/mace_walker.gd"),
	preload("res://src/sim/types/mace_ball.gd"),
	preload("res://src/sim/types/lantern_walker.gd"),
	preload("res://src/sim/types/spear_guard.gd"),
]
const Moves = preload("res://src/sim/moves.gd")
const Collision = preload("res://src/sim/collision.gd")
const Constants = preload("res://src/sim/script_constants.gd")
const LEVEL_FIELDS := [["dynamic_serial", 1], ["modal_token", 0]]
const TOKEN_BASE := 1_000_000
const MAX_DYNAMIC_SERIAL := 0x7fffffffffffffff - TOKEN_BASE
const Units = preload("res://src/sim/units.gd")
const S := Units.SCALE
const MAX_OPTION_PIXELS := 0x7fffffffffffffff / S - 1
const WAITING := 0
const ACTIVE := 1
const QUEUED := 2
const DEFEATED := 3
const COMMON_FIELDS := [
	["source_index", 0],
	["token", 0],
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

static var _ordered_level_fields := compose_level_schema()
# Dispatch caches. Types and their constants never change at run time, so these
# answer exactly what a scan of TYPES and get_script_constant_map() would.
static var _by_code := compose_lookup()
static var _enemy_codes := {}
# Each code's ordered schema is composed once and shared read-only.
static var _fields_by_code := {}
static var _facts_by_code := {}


static func lookup(code: String) -> Script:
	return _by_code.get(code, Inert)


## Per-code dispatch facts for the per-entity loops: the type, its phases and which
## optional hooks it has. Read once per code; the answers equal lookup(),
## phase_for() and has_method() on the type.
static func facts(code: String) -> Dictionary:
	var cached: Variant = _facts_by_code.get(code)
	if cached == null:
		var type := lookup(code)
		cached = {
			"type": type,
			"step_phase": phase_for(type, "STEP_PHASE", 0),
			"contact_phase":
			phase_for(type, "CONTACT_PHASE", 1) if type.has_method("contact") else -1,
			"consume": type.has_method("consume_requests"),
			"finished": type.has_method("finished"),
			"toggle": type.has_method("toggle"),
		}
		_facts_by_code[code] = cached
	return cached


## The first type in TYPES that lists a code wins, as the original linear scan did.
static func compose_lookup() -> Dictionary:
	var result := {}
	for type: Script in TYPES:
		for code: String in type.CODES:
			if not result.has(code):
				result[code] = type
	return result


## A type's script constant, read once per type. Callers must not mutate the value.
static func constant(type: Script, key: String, fallback: Variant = null) -> Variant:
	return Constants.read(type, key, fallback)


static func implemented(code: String) -> bool:
	return lookup(code) != Inert


## The shared, read-only field schema of a code. Copy it before changing it.
static func fields(code: String) -> Array:
	var cached: Variant = _fields_by_code.get(code)
	if cached == null:
		var result := COMMON_FIELDS.duplicate(true)
		result.append_array(lookup(code).FIELDS.duplicate(true))
		for pair: Array in result:
			pair.make_read_only()
		result.make_read_only()
		_fields_by_code[code] = result
		cached = result
	return cached


static func level_fields() -> Array:
	return _ordered_level_fields.duplicate(true)


static func compose_level_schema() -> Array:
	var result := LEVEL_FIELDS.duplicate(true)
	var names := {}
	for pair: Array in LEVEL_FIELDS:
		names[pair[0]] = true
	for type: Script in TYPES:
		for pair: Array in type.get_script_constant_map().get("LEVEL_FIELDS", []):
			assert(not names.has(pair[0]), "Duplicate level field: " + pair[0])
			names[pair[0]] = true
			result.append(pair.duplicate())
	return result


static func valid_state(state: Dictionary) -> bool:
	if (
		not state.get("dynamic_serial") is int
		or state.dynamic_serial < 1
		or state.dynamic_serial > MAX_DYNAMIC_SERIAL + 1
	):
		return false
	if not state.get("modal_token") is int or state.modal_token < 0:
		return false
	if state.modal_token:
		var holder := find_token(state, state.modal_token)
		if (
			holder.is_empty()
			or not holder.get("code") is String
			or holder.get("status") != ACTIVE
			or not lookup(holder.code).has_method("modal_step")
		):
			return false
	for type: Script in TYPES:
		if type.has_method("valid_state") and not type.valid_state(state):
			return false
	return true


static func modal_step(state: Dictionary, world: Dictionary, input: int) -> bool:
	if not state.modal_token:
		return false
	var holder := find_token(state, state.modal_token)
	if holder.is_empty():
		state.modal_token = 0
		return false
	var type := lookup(holder.code)
	var paused: bool = (
		type.has_method("modal_step") and type.modal_step(holder, state, world, input)
	)
	if not paused:
		state.modal_token = 0
	return paused


static func consume_requests(state: Dictionary, world: Dictionary) -> void:
	for type: Script in TYPES:
		if type.has_method("consume_level_requests"):
			type.consume_level_requests(state, world)
	var solids := Collision.solid_rows(world)
	for entity: Dictionary in state.entities:
		var known: Dictionary = facts(entity.code)
		if known.consume:
			var row: Variant = _solid_row(solids, entity)
			if row != null:
				Collision.dispatch_begin(world, row)
			known.type.consume_requests(entity, state, world)
			if row != null:
				Collision.dispatch_end(world, row)


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
		var compiled := compile_object(source_id, objects[source_id], world)
		if not compiled.ok:
			return {"ok": false, "error": compiled.error}
		var source: Dictionary = compiled.source
		if source.has("placeholder"):
			print("Unsupported object %s (%s)" % [source.properties.A, source.placeholder])
		elif is_enemy(source.code):
			source.family_index = world.enemies.size()
			world.enemies.append(source)
		elif source.code == "o11":
			source.family_index = world.springs.size()
			world.springs.append(source)
		elif source.code == "p1":
			world.bridges.append(source)
		elif source.code == "o5":
			world.goals.append([source.x, source.y])
		world.entities.append(source)
	return {"ok": true}


## Malformed data fails the level. An unregistered code, or a variant a type does not
## build yet, compiles to an inert placeholder that keeps its id, position and properties.
static func compile_object(source_id: Variant, raw_value: Variant, world: Dictionary) -> Dictionary:
	if not source_id is String or not raw_value is Dictionary or not raw_value.get("A") is String:
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
		"layer": 8 if is_enemy(code) else 7,
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
	var base := source.duplicate(true)
	var type := lookup(code)
	if type == Inert:
		return {"ok": true, "source": placeholder(base, "unregistered code", false)}
	if is_enemy(code):
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
	elif code == "o11":
		var value: Variant = raw.get("F", 0)
		if (
			not finite_number(value)
			or value != floor(value)
			or value < 0
			or value > MAX_OPTION_PIXELS
		):
			return {"ok": false, "error": "Invalid pad variant"}
		if value > 3:
			return {"ok": true, "source": placeholder(base, "pad variant F=%d" % int(value))}
		source.variant = int(value)
		source.y += 16 * S
		source.large = source.variant % 2
		source.single_use = int(source.variant >= 2)
	elif code == "p1":
		var width := numeric_option(raw.get("E1"))
		if not width.ok or width.value < 0:
			return {"ok": false, "error": "Invalid bridge width"}
		var size := roundi(width.value * S)
		source.left = source.x - size / 2
		source.right = source.x + size / 2
		source.top = source.y - 16 * S
	elif code == "o6":
		for key: String in ["E1", "E2"]:
			var parsed := numeric_option(raw.get(key))
			if not parsed.ok:
				return {"ok": false, "error": "Invalid checkpoint position: " + key}
			source["respawn_x" if key == "E1" else "respawn_y"] = roundi(parsed.value * S)
	var checked: Dictionary = (
		type.prepare(source, world) if type.has_method("prepare") else {"ok": true}
	)
	if checked.get("ok", false):
		# A type may also refuse an unbuilt form when it creates state.
		var created: Variant = type.create(source, world)
		if created is Dictionary and created.has("ok") and not created.ok:
			checked = created
	if checked.get("ok", false):
		return {"ok": true, "source": source}
	var reason := str(checked.get("error", "Invalid placement options"))
	if checked.get("degrade", false):
		return {"ok": true, "source": placeholder(base, reason)}
	return {"ok": false, "error": reason}


## A placeholder keeps the placement's id, token, position and raw properties. A known code
## gets the marker prefix so dispatch, family views and saved schema select the inert type.
static func placeholder(base: Dictionary, reason: String, known: bool = true) -> Dictionary:
	var source := base.duplicate(true)
	if known:
		source.code = PLACEHOLDER_PREFIX + base.code
	source.family_index = 0
	source.placeholder = reason
	return source


static func placeholder_reason(source: Dictionary) -> String:
	return str(source.get("placeholder", ""))


static func degraded(source: Dictionary) -> bool:
	return str(source.get("code", "")).begins_with(PLACEHOLDER_PREFIX)


static func spawn_dynamic(
	state: Dictionary, world: Dictionary, code: String, x: int, y: int, options: Dictionary
) -> Dictionary:
	var type := lookup(code)
	if type == Inert or not constant(type, "DYNAMIC", false):
		return spawn_error("Object type does not permit runtime creation: " + code)
	if not state.get("dynamic_serial") is int or state.dynamic_serial < 1:
		return spawn_error("Invalid runtime creation serial")
	var serial: int = state.dynamic_serial
	var used := {}
	for entity: Dictionary in state.entities:
		used[entity.id] = true
	while serial <= MAX_DYNAMIC_SERIAL and used.has("+%d" % serial):
		serial += 1
	if serial > MAX_DYNAMIC_SERIAL:
		return spawn_error("Runtime creation serial is exhausted")
	var source := {
		"source_index": -1,
		"id": "+%d" % serial,
		"code": code,
		"x": x,
		"y": y,
		"properties": options.duplicate(true),
		"variant": 0,
		"mirror": 0,
		"rotation": 0,
		"layer": 8 if is_enemy(code) else 7,
		"family_index": state.get("enemies", []).size() if is_enemy(code) else 0
	}
	for pair: Array in [["F", "variant"], ["M", "mirror"], ["R", "rotation"]]:
		var value: Variant = options.get(pair[0], 0)
		if (
			not finite_number(value)
			or value != floor(value)
			or value < -MAX_OPTION_PIXELS
			or value > MAX_OPTION_PIXELS
		):
			return spawn_error("Invalid runtime placement option: " + pair[0])
		source[pair[1]] = int(value)
	if type.has_method("prepare"):
		var prepared: Dictionary = type.prepare(source, world)
		if not prepared.get("ok", false):
			return spawn_error(str(prepared.get("error", "Invalid runtime options")))
	var entity := create(source, world)
	# Placement-style options go through prepare/create. Runtime values must be saved fields.
	var writable := ["vx", "vy", "facing", "layer", "can_despawn", "despawn_radius"]
	for pair: Array in type.FIELDS:
		writable.append(pair[0])
	for key: Variant in options:
		if key in writable:
			if not options[key] is int:
				return spawn_error("Runtime state must be int64: " + str(key))
			entity[key] = options[key]
		elif key not in ["F", "M", "R", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8"]:
			return spawn_error("Unknown runtime creation option: " + str(key))
	entity.token = TOKEN_BASE + serial
	entity.spawn_mode = 0
	entity.can_respawn = 0
	entity.status = ACTIVE
	if not valid(entity):
		return spawn_error("Runtime options produce invalid entity state")
	if type.has_method("activate"):
		type.activate(entity, state, world)
	state.dynamic_serial = serial + 1
	state.entities.append(entity)
	attach_views(state)
	return entity


static func spawn_error(message: String) -> Dictionary:
	if OS.is_debug_build():
		push_warning(message)
	return {}


static func dynamic_number(id: String) -> int:
	if not id.begins_with("+"):
		return -1
	var digits := id.substr(1)
	var maximum := str(MAX_DYNAMIC_SERIAL)
	if digits.is_empty() or digits.length() > maximum.length():
		return -1
	for index in digits.length():
		if digits.unicode_at(index) < 48 or digits.unicode_at(index) > 57:
			return -1
	if digits.length() == maximum.length() and digits > maximum:
		return -1
	var value := digits.to_int()
	return value if value > 0 and str(value) == digits else -1


static func find_token(state: Dictionary, token: int) -> Dictionary:
	if token > 0 and state.get("entities") is Array:
		for entity: Variant in state.entities:
			if entity is Dictionary and entity.get("token") == token:
				return entity
	return {}


static func compact(state: Dictionary) -> void:
	# Call once after all contacts and request consumers, never during table iteration.
	var captor_token := 0
	if state.captured_by > 0 and state.captured_by <= state.enemies.size():
		captor_token = state.enemies[state.captured_by - 1].token
	var remaining := []
	for entity: Dictionary in state.entities:
		var known: Dictionary = facts(entity.code)
		if (
			entity.source_index == -1
			and entity.status == DEFEATED
			and entity.token != state.get("move_held_id", 0)
			and entity.token != captor_token
			and entity.get("held", 0) != 1
			and (not known.finished or known.type.finished(entity))
		):
			continue
		remaining.append(entity)
	state.entities = remaining
	attach_views(state)
	if state.captured_by:
		var captor := find_token(state, captor_token)
		state.captured_by = captor.family_index + 1 if not captor.is_empty() else 0


static func tongue_contact(state: Dictionary, world: Dictionary, box: Array) -> void:
	if box.size() != 4 or state.get("move_held_id", 0):
		return
	for entity: Dictionary in state.entities:
		var type := lookup(entity.code)
		if entity.status != ACTIVE or entity.get("held", 0) == 1 or entity.get("hidden", 0) == 1:
			continue
		if not overlaps_box(entity, type, box):
			continue
		var result := 0
		if type.has_method("tongue"):
			var row: Variant = _solid_row(Collision.solid_rows(world), entity)
			if row != null:
				Collision.dispatch_begin(world, row)
			result = type.tongue(entity, state, world)
			if row != null:
				Collision.dispatch_end(world, row)
		elif phase_for(type, "SOLID", 0) == 1:
			for solid: Array in solid_boxes(entity, type):
				if (
					box[2] > solid[0]
					and box[0] < solid[2]
					and box[3] > solid[1]
					and box[1] < solid[3]
				):
					result = 2
					break
		if result == 1:
			return
		if result == 2:
			Moves.block_tongue(state)
			return


static func solid_boxes(entity: Dictionary, type: Script) -> Array:
	if type.has_method("solid_boxes"):
		return type.solid_boxes(entity)
	if type.has_method("solid_box"):
		var box: Array = type.solid_box(entity)
		return [] if box.is_empty() else [box]
	return []


static func toggle_switch(state: Dictionary, world: Dictionary) -> void:
	# Switch links are map-wide, not limited to the camera or active entities.
	var solids := Collision.solid_rows(world)
	for entity: Dictionary in state.entities:
		var known: Dictionary = facts(entity.code)
		if known.toggle:
			var row: Variant = _solid_row(solids, entity)
			if row != null:
				Collision.dispatch_begin(world, row)
			known.type.toggle(entity, state, world)
			if row != null:
				Collision.dispatch_end(world, row)


## This step's solid index row for an entity, or null. See Collision.refresh.
static func _solid_row(solids: Dictionary, entity: Dictionary) -> Variant:
	if solids.is_empty():
		return null
	var row: Variant = solids.get(entity.token)
	return row if row != null and is_same(row.entity, entity) else null


## Entities whose bounds may overlap `box` ([left, top, right, bottom], simulation units),
## in entity order. Touching edges count, so the result is a superset of strict overlap.
## It includes every status; callers keep their own status, held and hidden checks.
## Use it instead of iterating state.entities for an area query.
static func nearby(state: Dictionary, _world: Dictionary, box: Array) -> Array:
	var result := []
	var left: int = box[0]
	var top: int = box[1]
	var right: int = box[2]
	var bottom: int = box[3]
	for entity: Dictionary in state.entities:
		var type: Script = _by_code.get(entity.code, Inert)
		var x: int = entity.x
		var y: int = entity.y
		if not type.has_method("bounds"):
			if x >= left and x <= right and y >= top and y <= bottom:
				result.append(entity)
			continue
		var bounds: Array = type.bounds(entity)
		if (
			x + bounds[2] >= left
			and x + bounds[0] <= right
			and y + bounds[3] >= top
			and y + bounds[1] <= bottom
		):
			result.append(entity)
	return result


static func overlaps_box(entity: Dictionary, type: Script, box: Array) -> bool:
	var bounds: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
	return (
		entity.x + bounds[2] > box[0]
		and entity.x + bounds[0] < box[2]
		and entity.y + bounds[3] > box[1]
		and entity.y + bounds[1] < box[3]
	)


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
	entity.token = entity.source_index + 1
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
			if entity.source_index >= 0 and entity.map_index == world.get("map_index", 0):
				previous[entity.id] = entity.checkpoint_collected
	if not keep_flags:
		# These references belong to the table that is about to be replaced.
		Moves.interrupt(state)
		for field: String in [
			"move_held_id",
			"move_digest",
			"move_instant",
			"move_digest_ticks",
			"move_ammo",
			"move_ammo_count"
		]:
			state[field] = 0
		state.move_held_speed = 256 * 60
		# Placed tokens repeat in the next table, so old emissions must not survive it.
		for pair: Array in Moves.PLAYER_FIELDS:
			if pair[0].begins_with("move_emit_"):
				state[pair[0]] = pair[1]
	state.captured_by = 0
	state.modal_token = 0
	for type: Script in TYPES:
		if type.has_method("reset_map"):
			type.reset_map(state, world)
	state.entities = []
	for source: Dictionary in world.get("entities", []):
		var entity := create(source, world)
		if previous.has(entity.id):
			entity.collected = previous[entity.id]
			entity.checkpoint_collected = previous[entity.id]
		state.entities.append(entity)
	attach_views(state)


static func attach_views(state: Dictionary, reindex: bool = true) -> void:
	# Transitional read views share dictionaries; they are not separate saved state.
	state.enemies = []
	state.springs = []
	for entity: Dictionary in state.entities:
		if is_enemy(entity.code):
			if reindex:
				entity.family_index = state.enemies.size()
			state.enemies.append(entity)
		elif entity.code == "o11":
			if reindex:
				entity.family_index = state.springs.size()
			state.springs.append(entity)


static func is_enemy(code: String) -> bool:
	var cached: Variant = _enemy_codes.get(code)
	if cached == null:
		cached = code in Actor.CODES or bool(constant(lookup(code), "ENEMY", false))
		_enemy_codes[code] = cached
	return cached


static func source_for(entity: Dictionary, world: Dictionary) -> Dictionary:
	if entity.source_index >= 0:
		return world.entities[entity.source_index]
	# Dynamic types keep every option they need in their saved schema.
	var source := entity.duplicate()
	source.properties = entity.duplicate()
	source.variant = int(entity.get("variant", 0))
	source.mirror = 1 if entity.facing > 0 else 0
	source.rotation = int(entity.get("rotation", 0))
	return source


static func phase_for(type: Script, key: String, fallback: int) -> int:
	return int(constant(type, key, fallback))


static func advance(state: Dictionary, world: Dictionary, pressed: int) -> void:
	state.pressed_input = pressed
	# Preserve actor movement before pad gravity, including capture's early exit.
	for phase in [0, 1]:
		if phase == 1 and state.captured_by:
			break
		var solids := Collision.solid_rows(world)
		for entity: Dictionary in state.entities:
			var known: Dictionary = facts(entity.code)
			if known.step_phase != phase:
				continue
			var type: Script = known.type
			var row: Variant = _solid_row(solids, entity)
			if row != null:
				Collision.dispatch_begin(world, row)
			lifecycle(entity, state, world)
			if entity.status == ACTIVE:
				type.step(entity, state, world)
			if row != null:
				Collision.dispatch_end(world, row)


static func lifecycle(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status == DEFEATED or entity.get("held", 0) == 1:
		return
	# An active entity that cannot despawn has no transition below; skip the box work.
	if entity.status == ACTIVE and not entity.can_despawn:
		return
	var type := lookup(entity.code)
	var box := activation_box(entity, type)
	var far: bool = (
		box[0] > state.camera_x + entity.despawn_radius
		or box[2] < state.camera_x - entity.despawn_radius
		or box[1] > state.camera_y + entity.despawn_radius
		or box[3] < state.camera_y - entity.despawn_radius
	)
	if entity.source_index == -1:
		# A runtime entity has no immutable camera-respawn anchor.
		if entity.status == ACTIVE and entity.can_despawn and far:
			if type.has_method("deactivate"):
				type.deactivate(entity, state, world)
			entity.status = DEFEATED
		return
	var source := source_for(entity, world)
	if entity.status == ACTIVE and entity.can_despawn and far:
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
		box = activation_box(entity, type)
		if (
			box[2] > state.camera_x - entity.activation_x
			and box[0] < state.camera_x + entity.activation_x
			and box[3] > state.camera_y - entity.activation_y
			and box[1] < state.camera_y + entity.activation_y
		):
			entity.status = ACTIVE
			if source.mirror == 2:
				entity.facing = -1 if state.x < entity.x else 1
			if type.has_method("activate"):
				type.activate(entity, state, world)


static func activation_box(entity: Dictionary, type: Script) -> Array:
	if type.has_method("activation_bounds"):
		return type.activation_bounds(entity)
	var box: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
	return [entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]]


static func contact(state: Dictionary, input: int, world: Dictionary) -> void:
	for phase in [0, 1, 2]:
		for entity: Dictionary in state.entities:
			var known: Dictionary = facts(entity.code)
			if (
				known.contact_phase == phase
				and entity.status == ACTIVE
				and entity.get("held", 0) != 1
				and entity.get("hidden", 0) != 1
			):
				var row: Variant = _solid_row(Collision.solid_rows(world), entity)
				if row != null:
					Collision.dispatch_begin(world, row)
				known.type.contact(entity, state, world, input)
				if row != null:
					Collision.dispatch_end(world, row)


static func goal_convert(state: Dictionary, world: Dictionary, on_coin: Callable) -> void:
	if not on_coin.is_valid():
		return
	for entity: Dictionary in state.entities:
		var type := lookup(entity.code)
		if (
			entity.status != ACTIVE
			or entity.get("held", 0) == 1
			or entity.get("hidden", 0) == 1
			or not constant(type, "GOAL_COIN", false)
		):
			continue
		var bounds: Array = type.bounds(entity)
		if (
			entity.x + bounds[2] > state.camera_x - 416 * S
			and entity.x + bounds[0] < state.camera_x + 416 * S
			and entity.y + bounds[3] > state.camera_y - 224 * S
			and entity.y + bounds[1] < state.camera_y + 224 * S
		):
			entity.status = DEFEATED
			Collision.refresh(world, entity)
			on_coin.call(state)


static func valid(entity: Dictionary) -> bool:
	if not entity.get("code") is String or not entity.get("id") is String:
		return false
	var declared := fields(entity.code)
	if entity.size() != declared.size() + 2:
		return false
	for pair: Array in declared:
		if not entity.get(pair[0]) is int:
			return false
	for key: String in [
		"collected", "checkpoint_collected", "offscreen", "spawn_mode", "can_despawn", "can_respawn"
	]:
		if entity[key] not in [0, 1]:
			return false
	for key: String in [
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
	if entity.source_index >= 0:
		if entity.source_index >= TOKEN_BASE - 1 or entity.token != entity.source_index + 1:
			return false
	elif entity.source_index == -1:
		var serial := dynamic_number(entity.id)
		if (
			serial < 1
			or entity.token != TOKEN_BASE + serial
			or not implemented(entity.code)
			or not constant(lookup(entity.code), "DYNAMIC", false)
			or entity.can_respawn
			or entity.spawn_mode
		):
			return false
	else:
		return false
	return lookup(entity.code).valid(entity)


static func valid_table(state: Dictionary) -> bool:
	if (
		not state.get("entities") is Array
		or not state.get("dynamic_serial") is int
		or state.dynamic_serial < 1
		or state.dynamic_serial > MAX_DYNAMIC_SERIAL + 1
	):
		return false
	var ids := {}
	var dynamic := false
	for index in state.entities.size():
		var entity: Variant = state.entities[index]
		if not entity is Dictionary or not valid(entity) or ids.has(entity.id):
			return false
		ids[entity.id] = true
		if entity.map_index != state.get("map_index", 0):
			return false
		if entity.source_index == -1:
			dynamic = true
			if dynamic_number(entity.id) >= state.dynamic_serial:
				return false
		elif dynamic or entity.source_index != index:
			return false
	return true


static func valid_world(state: Dictionary, world: Dictionary) -> bool:
	if not valid_table(state) or state.entities.size() < world.get("entities", []).size():
		return false
	for index in state.entities.size():
		var entity: Dictionary = state.entities[index]
		if index >= world.entities.size():
			if entity.source_index != -1:
				return false
		elif (
			entity.source_index != index
			or entity.id != world.entities[index].id
			or entity.code != world.entities[index].code
		):
			return false
	return true
