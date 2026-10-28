extends RefCounted
## A balloon with a top-only deck that rises and drifts at its placement speeds,
## optionally bobbing. Landing on it pauses it for a moment; while the player
## stands on it, it rises at a fifth of its speed and stops bobbing.

const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const CODES := ["o26"]
const SOLID := 2
const CONTACT_PHASE := 1
const FIELDS := [
	["form", 0],
	["rise", 0],
	["drift", 0],
	["bob", 0],
	["bob_period", 240],
	["age", 0],
	["stepped", 0],
	["land_delay", 0]
]
const BOX := [-30 * S, -30 * S, 30 * S, 30 * S]
const LAND_TICKS := 6  # 0.1 s pause after a landing.
const MAX_OPTION := 100_000


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := []
	for pair: Array in [["E1", "0"], ["E2", "0"], ["E3", "0"], ["E4", "4"]]:
		var raw: Variant = source.properties.get(pair[0], pair[1])
		var parsed: Dictionary = registry().numeric_option(
			pair[1] if raw is String and raw.strip_edges() == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid balloon option: " + pair[0]}
		if absf(parsed.value) > MAX_OPTION:
			return {
				"ok": false, "degrade": true, "error": "balloon option %s out of range" % pair[0]
			}
		values.append(int(parsed.value))
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form < 0 or form != floor(form):
		return {"ok": false, "error": "Invalid balloon colour"}
	source.form = int(form)
	source.rise = values[0]
	source.drift = values[1]
	source.bob = 32 * values[2]
	source.bob_period = maxi(1, values[3] * 60)
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"form": int(source.form),
		"rise": int(source.rise),
		"drift": int(source.drift),
		"bob": int(source.bob),
		"bob_period": int(source.bob_period),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - 30 * S, entity.y - 20 * S, entity.x + 30 * S, entity.y - 18 * S]


## Vertical bob offset in units for an age, a sine of the given period.
static func bob_offset(entity: Dictionary, age: int) -> int:
	if entity.bob == 0:
		return 0
	var phase: int = posmod(age, entity.bob_period) * 360000 / entity.bob_period
	return entity.bob * Motion.turn_sine(phase)


static func step(entity: Dictionary, _state: Dictionary, world: Dictionary) -> void:
	if entity.land_delay:
		entity.land_delay -= 1
		entity.vy = 0
	else:
		entity.vx = entity.drift * 60
		entity.vy = -entity.rise * 60 / (4 * entity.stepped + 1)
	var dx: int = entity.vx
	if dx:
		Motion.move(entity, world, BOX, dx, true)
	var dy: int = entity.vy
	if dy and Collision.prepare(entity, world, BOX):
		Collision.vertical(entity, world, BOX, dy, 0)
	if not entity.stepped and entity.bob:
		entity.y += bob_offset(entity, entity.age + 1) - bob_offset(entity, entity.age)
		entity.age = posmod(entity.age + 1, entity.bob_period)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	var box := Moves.player_box(state)
	var feet: int = state.y + box[3]
	var top: int = entity.y - 20 * S
	var on_deck: bool = (
		state.x + box[2] >= entity.x - 30 * S
		and state.x + box[0] <= entity.x + 30 * S
		and feet <= top + 2 * S
		and feet + 4 * S >= top
	)
	if on_deck and not entity.stepped:
		entity.land_delay = LAND_TICKS
		entity.vy = 0
		entity.stepped = int(state.on_floor)
	elif entity.stepped and not on_deck:
		entity.stepped = 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "frame": entity.form}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.form >= 0
		and absi(entity.rise) <= MAX_OPTION
		and absi(entity.drift) <= MAX_OPTION
		and absi(entity.bob) <= 32 * MAX_OPTION
		and entity.bob_period >= 1
		and entity.age >= 0
		and entity.age < entity.bob_period
		and entity.stepped in [0, 1]
		and entity.land_delay >= 0
		and entity.land_delay <= LAND_TICKS
	)
