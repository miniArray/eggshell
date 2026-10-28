extends RefCounted
## A flyer that crosses the level level-straight at its placement speed, through
## terrain, bobbing up and down on a sine. Landing on it defeats it; touching it
## otherwise hurts.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e43"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const MAX_OPTION := 100_000
const FIELDS := (
	Body.FIELDS + [["speed", 192], ["bob", 2], ["bob_period", 30], ["age", 0], ["contact", 0]]
)


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var result := Options.prepare(source, 0)
	if not result.ok:
		return result
	var values := []
	for pair: Array in [["E1", "2"], ["E2", "0.5"], ["E3", "192"]]:
		var raw: Variant = source.properties.get(pair[0], pair[1])
		var parsed: Dictionary = registry().numeric_option(
			pair[1] if raw is String and raw.strip_edges() == "" else raw
		)
		if not parsed.ok:
			return {"ok": false, "error": "Invalid flyer option: " + pair[0]}
		if absf(parsed.value) > MAX_OPTION:
			return {"ok": false, "degrade": true, "error": "flyer option %s out of range" % pair[0]}
		values.append(parsed.value)
	source.bob = int(values[0])
	# The period keeps fractions of a second; ticks round up.
	source.bob_period = maxi(1, ceili(values[1] * 60.0 - 0.000001))
	if absf(values[2]) > Options.MAX_SPEED / 60:
		return {"ok": false, "degrade": true, "error": "flyer speed E3 out of range"}
	source.speed = int(values[2])
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.speed = int(source.get("speed", 192))
	values.bob = int(source.get("bob", 2))
	values.bob_period = int(source.get("bob_period", 30))
	return values


static func bounds(entity: Dictionary) -> Array:
	return (
		[-16 * S, -8 * S, 14 * S, 12 * S]
		if entity.facing < 0
		else [-14 * S, -8 * S, 16 * S, 12 * S]
	)


static func bob_offset(entity: Dictionary, age: int) -> int:
	var phase: int = posmod(age, entity.bob_period) * 360000 / entity.bob_period
	return entity.bob * Motion.turn_sine(phase)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if action == Body.RELEASED:
		entity.spat = 0
		entity.vy = 0
	entity.vx = entity.facing * entity.speed * 60
	entity.x += entity.vx
	entity.y += bob_offset(entity, entity.age + 1) - bob_offset(entity, entity.age)
	entity.age = posmod(entity.age + 1, entity.bob_period)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching and not entity.contact and entity.y > state.y - 8 * S:
		if not Body.pounding(state):
			Moves.bounce(state, -320 * 60, input)
		Body.remove(entity, state)
	elif touching and entity.y < state.y - 8 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if projectile.has("fall_on_terrain"):
		projectile.fall_on_terrain = 1
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": "Fly"}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and absi(entity.speed) <= MAX_OPTION
		and absi(entity.bob) <= MAX_OPTION
		and entity.bob_period >= 1
		and entity.age >= 0
		and entity.age < entity.bob_period
		and entity.contact in [0, 1]
	)
