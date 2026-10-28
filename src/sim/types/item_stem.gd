extends RefCounted
## A periodic producer uses the same saved runtime table as its released items.

const CODES := ["o17"]
const S := preload("res://src/sim/units.gd").SCALE
const Motion = preload("res://src/sim/item_motion.gd")
const Math = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const PAYLOADS := ["o7", "o4", "e40", ""]
const FIELDS := [
	["payload", 0],
	["phase", 0],
	["fast", 0],
	["fast_loop", 0],
	["impact_cursor", 0],
	["unavailable", 0]
]


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var payload: Variant = source.properties.get("E1", "")
	if not payload is String:
		return {"ok": false, "error": "Invalid producer payload"}
	if payload == "":
		payload = "o7"
	var index := PAYLOADS.find(payload)
	source.payload = 3 if index < 0 else index
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"payload": int(source.payload),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(_entity: Dictionary) -> Array:
	return [-10 * S, -24 * S, 10 * S, 16 * S]


static func activate(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	# The first loop begins at frame one, after the half-duration first frame.
	entity.phase = 3
	entity.impact_cursor = state.move_impact


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	consume_requests(entity, state, world)
	Motion.fall(entity, world, bounds(entity), 2048, 704 * 60)
	entity.phase += 1
	if entity.phase < (30 if entity.fast_loop else 66):
		return
	var available := amount(entity, state)
	var burst := mini(10 if entity.fast else 1, available)
	entity.fast_loop = entity.fast
	for index in burst:
		release(entity, state, world)
	if entity.fast and burst >= 2:
		entity.fast = 0
		entity.fast_loop = 0
	entity.phase = 0


static func amount(entity: Dictionary, state: Dictionary) -> int:
	if entity.payload in [0, 2]:
		var eggs: Script = registry().lookup("o7")
		return maxi(0, 6 - eggs.active_count(state))
	if entity.payload == 1:
		return maxi(0, 30 - state.health)
	return 0


static func release(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.unavailable:
		return
	var gravity: int = [1600, 1024, 1536, 1600][entity.payload]
	var options := {
		"vx": Math.random_ticks(state, -176 * 60, 176 * 60),
		"vy": -Math.root(2 * gravity * 144 * 3600),
		"can_despawn": 1
	}
	if entity.payload != 2:
		# Only pickups ignore terrain and wait before collection; spiked bodies collide.
		options.pickup_delay = 6
		options.ignore_terrain = 1
	if entity.payload == 1:
		options.wait_for_land = 1
	var made: Dictionary = registry().spawn_dynamic(
		state, world, PAYLOADS[entity.payload], entity.x, entity.y - 40 * S, options
	)
	if made.is_empty():
		entity.unavailable = 1


static func consume_requests(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if entity.impact_cursor == state.move_impact:
		return
	entity.impact_cursor = state.move_impact
	if entity.status == 1 and state.move_impact:
		entity.fast = 1
		if not entity.fast_loop and entity.phase >= 3 and entity.phase < 51:
			entity.phase = 51


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind == Hits.BUMP:
		entity.vy = -384 * 60


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	# Loop and FastLoop are the literal pack names for the two release cycles.
	var frame := 0
	if entity.phase >= 3:
		var tail := 21 if entity.fast_loop else 57
		frame = (
			1 + (entity.phase - 3) / 6
			if entity.phase < tail
			else (4 if entity.fast_loop else 10) + (entity.phase - tail) / 3
		)
	return {
		"visible": entity.status == 1,
		"animation": "FastLoop" if entity.fast_loop else "Loop",
		"frame": frame
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.payload >= 0
		and entity.payload <= 3
		and entity.phase >= 0
		and entity.phase < (30 if entity.fast_loop else 66)
		and entity.fast in [0, 1]
		and entity.fast_loop in [0, 1]
		and entity.impact_cursor >= 0
		and entity.unavailable in [0, 1]
		and entity.vx >= -1024 * 60
		and entity.vx <= 1024 * 60
		and entity.vy >= -1024 * 60
		and entity.vy <= 1024 * 60
	)
