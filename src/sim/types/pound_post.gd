extends RefCounted
## Bottom-anchored posts shorten under a pound; the pointed form causes contact damage.
const CODES := ["o23"]
const SOLID := 1
const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Moves = preload("res://src/sim/moves.gd")
const Damage = preload("res://src/sim/damage.gd")
const World = preload("res://src/sim/world.gd")
const FIELDS := [["height", 0], ["colour", 0], ["spiked", 0]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var values := []
	for key: String in ["E1", "E2", "E3"]:
		var raw: Variant = source.properties.get(key, "0")
		var parsed: Dictionary = registry.numeric_option(
			"0" if raw is String and raw == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid post option: " + key}
		values.append(int(parsed.value))
	if values[0] < 0 or values[1] < 0 or values[2] < 0:
		return {"ok": false, "error": "Invalid post size, colour or pointed form"}
	if values[1] > 16 or values[2] > 1:
		return {
			"ok": false,
			"degrade": true,
			"error": "post colour E2=%d or pointed form E3=%d" % [values[1], values[2]]
		}
	source.post_height = values[0] * S
	source.post_colour = values[1]
	source.post_spiked = values[2]
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"height": int(source.post_height),
		"colour": int(source.post_colour),
		"spiked": int(source.post_spiked),
		"layer": 9
	}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(entity: Dictionary) -> Array:
	return [-16 * S, -entity.height, 16 * S, 0]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.height == 0:
		return []
	return [entity.x - 16 * S, entity.y - entity.height, entity.x + 16 * S, entity.y]


static func bump(entity: Dictionary, state: Dictionary, world: Dictionary, side: int) -> void:
	if side != 1 or entity.spiked or entity.status != 1 or entity.height == 0:
		return
	var box := solid_box(entity)
	Collision.strike_above(entity, state, world, box, 2)
	var player := Moves.player_box(state)
	state.y = box[1] - player[3] - S / 16
	for part in 2:
		var foot: int = state.y + player[3] + 2 * S
		if (
			_ground_at(state, world, state.x - 12 * S, foot)
			or _ground_at(state, world, state.x + 12 * S, foot)
		):
			break
		state.y += 16 * S
	state.vy = 0
	if entity.height <= 48 * S:
		entity.status = 3
		entity.height = 16 * S
	else:
		entity.height -= 32 * S


static func _ground_at(state: Dictionary, world: Dictionary, x: int, y: int) -> bool:
	if World.overlaps_box(world, x, y, x, y):
		return true
	for bridge: Dictionary in world.bridges:
		if x >= bridge.left and x <= bridge.right and y >= bridge.top and y <= bridge.top + 32 * S:
			return true
	var registry := Collision.registry_for(world)
	if registry == null:
		return false
	for target: Dictionary in state.entities:
		var type: Script = registry.lookup(target.code)
		if target.status != 1 or not type.get_script_constant_map().get("POST_SUPPORT", false):
			continue
		var box: Array = type.bounds(target)
		if (
			x >= target.x + box[0]
			and x <= target.x + box[2]
			and y >= target.y + box[1]
			and y <= target.y + box[3]
		):
			return true
	return false


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if not entity.spiked or entity.status != 1 or entity.height == 0:
		return
	var box := Moves.player_box(state)
	if (
		state.x + box[2] >= entity.x - 16 * S
		and state.x + box[0] <= entity.x + 16 * S
		and state.y + box[3] + S / 10 >= entity.y - entity.height
		and state.y + box[1] + S / 10 <= entity.y
	):
		Damage.hurt(state, entity.x)


static func tongue(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 2 if not solid_box(entity).is_empty() else 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": true, "size_x": 32, "size_y": entity.height / S, "frame": entity.colour}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.height >= 0
		and entity.colour >= 0
		and entity.colour <= 16
		and entity.spiked in [0, 1]
	)
