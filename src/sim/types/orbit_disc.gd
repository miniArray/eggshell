extends RefCounted
## A spinning disc that orbits its block. It grows out to its radius over half a
## second, shrinks back when recalled, and hurts the player on contact.

const S := preload("res://src/sim/units.gd").SCALE
const Body = preload("res://src/sim/enemy_body.gd")
const Moves = preload("res://src/sim/moves.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const CODES := ["enemy_disc"]
const DYNAMIC := true
const STEP_PHASE := 1
const CONTACT_PHASE := 1
const EXTEND_TICKS := 30  # 0.5 s out or back.
const FIELDS := [
	["owner", 0],
	["offset", 0],
	["speed", 96],
	["radius", 96],
	["age", 0],
	["extend", 0],
	["retracting", 0]
]
const MAX_AGE := 1_000_000


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"can_despawn": 0}


## Disc half size: half scale at rest, full scale when out.
static func half(entity: Dictionary) -> int:
	return 8 * S + 8 * S * entity.extend / EXTEND_TICKS


static func bounds(entity: Dictionary) -> Array:
	var size := half(entity)
	return [-size, -size, size, size]


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	var owner: Dictionary = registry().find_token(state, entity.owner)
	if owner.is_empty() or owner.status != 1:
		entity.status = 3
		return
	entity.age = mini(MAX_AGE, entity.age + 1)
	if entity.retracting:
		entity.extend -= 1
		if entity.extend <= 0:
			entity.status = 3
			return
	else:
		entity.extend = mini(EXTEND_TICKS, entity.extend + 1)
	var angle: int = posmod(entity.offset + entity.speed * 1000 * entity.age / 60, 360000)
	var reach: int = entity.radius * S * entity.extend / EXTEND_TICKS
	entity.x = owner.x + reach * Motion.turn_cosine(angle) / S
	entity.y = owner.y + reach * Motion.turn_sine(angle) / S


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	var player := Moves.player_box(state)
	var size := half(entity)
	if Body.overlap(
		[entity.x - size, entity.y - size, entity.x + size, entity.y + size],
		[state.x + player[0], state.y + player[1], state.x + player[2], state.y + player[3]]
	):
		Body.hurt(entity, state)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var size := float(half(entity) * 2) / S
	return {"visible": entity.status == 1, "size_x": size, "size_y": size}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.owner >= 0
		and entity.offset >= 0
		and entity.offset <= 360000
		and absi(entity.speed) <= 100_000
		and absi(entity.radius) <= 100_000
		and entity.age >= 0
		and entity.age <= MAX_AGE
		and entity.extend >= 0
		and entity.extend <= EXTEND_TICKS
		and entity.retracting in [0, 1]
	)
