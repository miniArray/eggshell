extends RefCounted
## A ridable wheel with a top-only deck. Idle, it turns at its own rate. Shortly
## after the player stands on it, it travels in its arrow's direction, reflecting
## off solids, until the player falls below its deck. An optional lifetime starts
## with the first ride; when it runs out the wheel vanishes until camera respawn.

const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const CODES := ["o21"]
const SOLID := 2
const CONTACT_PHASE := 1
## `angle` is in 1/60000 degree so a whole-degree rate per second adds exactly per tick.
const TURN := 360 * 60000
const FIELDS := [
	["angle", 0],
	["turn_rate", 0],
	["speed", 0],
	["form", 0],
	["life", 0],
	["life_left", -1],
	["start", 0],
	["riding", 0],
	["shrink", 0]
]
const START_TICKS := 3  # 0.05 s after the player lands.
const SHRINK_TICKS := 6  # 0.1 s shrink before vanishing.
const BODY := [-31 * S, -31 * S, 31 * S, 31 * S]
const MAX_RATE := 100_000
const MAX_SPEED := 100_000
const MAX_LIFE := 100_000


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var registry: Script = load("res://src/sim/registry.gd")
	var values := []
	for pair: Array in [["E1", "0"], ["E2", "128"], ["E3", "0"]]:
		var raw: Variant = source.properties.get(pair[0], pair[1])
		var parsed: Dictionary = registry.numeric_option(
			pair[1] if raw is String and raw.strip_edges() == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid wheel option: " + pair[0]}
		values.append(parsed.value)
	var angle: Dictionary = registry.numeric_option(source.properties.get("R", 0))
	var form: Variant = source.properties.get("F", 0)
	if (
		not angle.ok
		or not (form is int or form is float)
		or not is_finite(form)
		or form < 0
		or form != floor(form)
	):
		return {"ok": false, "error": "Invalid wheel angle or form"}
	if absf(values[0]) > MAX_RATE or absf(values[1]) > MAX_SPEED or values[2] > MAX_LIFE:
		return {"ok": false, "degrade": true, "error": "wheel option out of range"}
	source.turn_rate = int(values[0])
	source.speed = int(values[1])
	# Lifetime keeps fractions of a second; ticks round up.
	source.life = maxi(0, ceili(values[2] * 60.0 - 0.000001))
	source.angle = posmod(roundi((angle.value - 90.0) * 60000.0), TURN)
	source.form = int(form)
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"angle": int(source.angle),
		"turn_rate": int(source.turn_rate),
		"speed": int(source.speed),
		"form": int(source.form),
		"life": int(source.life),
		"life_left": -1,
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(_entity: Dictionary) -> Array:
	return [-32 * S, -32 * S, 32 * S, 32 * S]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.shrink:
		return []
	return [entity.x - 22 * S, entity.y - 22 * S, entity.x + 22 * S, entity.y - 20 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.shrink:
		entity.shrink += 1
		if entity.shrink > SHRINK_TICKS:
			entity.shrink = 0
			entity.riding = 0
			entity.start = 0
			entity.status = 2  # Queued: back only through camera respawn.
			entity.offscreen = 0
		return
	if entity.start:
		entity.start -= 1
		if entity.start == 0:
			entity.riding = 1
			if entity.life > 0 and entity.life_left < 0:
				entity.life_left = entity.life
	if entity.life_left > 0:
		entity.life_left -= 1
		if entity.life_left == 0:
			entity.shrink = 1
			return
	if not entity.riding:
		entity.angle = posmod(entity.angle + entity.turn_rate * 1000, TURN)
		return
	travel(entity, state, world)


## Move one tick along the arrow. A blocked axis reflects that component, and the
## arrow follows the new direction.
static func travel(entity: Dictionary, _state: Dictionary, world: Dictionary) -> void:
	var milli: int = entity.angle / 60
	var vx: int = entity.speed * 60 * Motion.turn_cosine(milli) / S
	var vy: int = entity.speed * 60 * Motion.turn_sine(milli) / S
	var flipped := false
	if vx and Collision.overlaps(entity, world, BODY, vx, 0):
		vx = -vx
		flipped = true
	else:
		entity.x += vx
	if vy and Collision.overlaps(entity, world, BODY, 0, vy):
		vy = -vy
		flipped = true
	else:
		entity.y += vy
	if flipped:
		entity.angle = Motion.angle_to(vx, vy) * 60


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.shrink:
		return
	var box := Moves.player_box(state)
	var feet: int = state.y + box[3]
	var top: int = entity.y - 22 * S
	var standing: bool = (
		state.on_floor
		and state.x + box[2] >= entity.x - 22 * S
		and state.x + box[0] <= entity.x + 22 * S
		and feet <= top
		and feet + 2 * S >= top
	)
	if entity.riding:
		if not standing and feet > entity.y - 16 * S:
			entity.riding = 0
	elif standing and not entity.start:
		entity.start = START_TICKS


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var size: float = 64.0 * (SHRINK_TICKS - maxi(0, entity.shrink - 1)) / SHRINK_TICKS
	return {
		"visible": entity.status == 1,
		"frame": entity.form,
		"rotation": float(entity.angle / 60000 + 90),
		"size_x": size,
		"size_y": size
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.angle >= 0
		and entity.angle < TURN
		and absi(entity.turn_rate) <= MAX_RATE
		and absi(entity.speed) <= MAX_SPEED
		and entity.form >= 0
		and entity.life >= 0
		and entity.life <= MAX_LIFE * 60
		and entity.life_left >= -1
		and entity.life_left <= entity.life
		and entity.start >= 0
		and entity.start <= START_TICKS
		and entity.riding in [0, 1]
		and entity.shrink >= 0
		and entity.shrink <= SHRINK_TICKS
	)
