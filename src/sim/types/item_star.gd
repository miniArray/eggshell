extends RefCounted
## Health drops are required by item impacts and screen clearing.

const CODES := ["o4"]
const DYNAMIC := true
const S := preload("res://src/sim/units.gd").SCALE
const Moves = preload("res://src/sim/moves.gd")
const Life = preload("res://src/sim/life.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Motion = preload("res://src/sim/item_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const FIELDS := [
	["held", 0],
	["request_cursor", 0],
	["pickup_delay", 0],
	["despawn_ticks", 0],
	["max_speed", 64 * 60],
	["wait_for_land", 0],
	["phase", 0],
	["ignore_terrain", 0],
	["origin_token", 0]
]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var mirror: Variant = source.properties.get("M", 0)
	if (
		not (mirror is int or mirror is float)
		or not is_finite(mirror)
		or mirror < 0
		or mirror != floor(mirror)
	):
		return {"ok": false, "error": "Invalid health drop direction"}
	if mirror > 2:
		return {"ok": false, "degrade": true, "error": "health drop direction M=%d" % mirror}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var placed := int(source.source_index >= 0)
	return {
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": placed,
		"can_respawn": placed,
		"phase": 0 if placed else 10
	}


static func bounds(entity: Dictionary) -> Array:
	return (
		[-12 * S, -18 * S, 12 * S, 16 * S]
		if entity.phase >= 10
		else [-12 * S, -20 * S, 12 * S, 14 * S]
	)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.held:
		consume_requests(entity, state, world)
		return
	entity.phase = mini(15, entity.phase + 1)
	entity.pickup_delay = maxi(0, entity.pickup_delay - 1)
	if entity.despawn_ticks:
		entity.despawn_ticks -= 1
		if not entity.despawn_ticks:
			entity.status = 3
			return
	var box := bounds(entity)
	if not entity.wait_for_land and not entity.ignore_terrain:
		if Collision.by_wall(entity, world, box, entity.facing):
			entity.facing = -entity.facing
		entity.vx = Motion.approach(entity.vx, entity.facing * entity.max_speed, 512)
	if Motion.fall(entity, world, box, 1024, 704 * 60):
		entity.vy = -288 * 60
		entity.max_speed = 64 * 60
		entity.phase = 0
		if entity.wait_for_land:
			entity.wait_for_land = 0
			entity.facing = -1 if state.x < entity.x else 1
	for name: String in ["lava", "lava_3"]:
		if World.named_overlaps(
			world, name, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
		):
			entity.status = 3
			return


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.collected or entity.pickup_delay or entity.held:
		return
	var body := Moves.player_box(state)
	var box := bounds(entity)
	if (
		entity.x + box[2] > state.x + body[0]
		and entity.x + box[0] < state.x + body[2]
		and entity.y + box[3] > state.y + body[1]
		and entity.y + box[1] < state.y + body[3]
	):
		collect(entity, state)


static func collect(entity: Dictionary, state: Dictionary) -> void:
	if Life.collect(state, Life.STAR, entity):
		if entity.origin_token:
			var registry: Script = load("res://src/sim/registry.gd")
			var origin: Dictionary = registry.find_token(state, entity.origin_token)
			if not origin.is_empty():
				origin.collected = 1
		entity.held = 0
		entity.status = 3


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.collected or entity.pickup_delay or Life.blocks_step(state):
		return 0
	if Moves.catch_item(state, entity.token, 0, 0, 0, 1):
		entity.held = 1
		entity.request_cursor = state.move_emit_serial
		return 1
	return 0


static func consume_requests(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if not entity.held:
		return
	var requests := Requests.since(state, entity.request_cursor)
	if not requests.ok:
		entity.request_cursor = state.move_emit_serial
		return
	for request: Dictionary in requests.requests:
		if request.item != entity.token:
			continue
		if request.kind == Requests.CONSUME:
			collect(entity, state)
		elif request.kind == Requests.SPIT:
			entity.held = 0
			entity.x = request.x
			entity.y = request.y
			entity.vx = request.vx
			entity.vy = request.vy
			entity.pickup_delay = 6
	entity.request_cursor = requests.latest


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	# Jump is the literal pack name for the three-frame hopping sequence.
	var period := 6 if entity.despawn_ticks < 120 else 12
	return {
		"visible": entity.status == 1 and not entity.held and not entity.collected,
		"animation": "Jump",
		"frame": mini(2, entity.phase / 5),
		"flip_x": entity.facing > 0,
		"modulate_alpha":
		(
			0.0
			if (
				entity.despawn_ticks > 0
				and entity.despawn_ticks < 240
				and entity.despawn_ticks % period >= period / 2
			)
			else 1.0
		)
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.held in [0, 1]
		and entity.request_cursor >= 0
		and entity.pickup_delay >= 0
		and entity.despawn_ticks >= 0
		and entity.max_speed >= 0
		and entity.max_speed <= 128 * 60
		and entity.wait_for_land in [0, 1]
		and entity.ignore_terrain in [0, 1]
		and entity.origin_token >= 0
		and entity.phase >= 0
		and entity.phase <= 15
		and entity.vx >= -1024 * 60
		and entity.vx <= 1024 * 60
		and entity.vy >= -1024 * 60
		and entity.vy <= 1024 * 60
	)
