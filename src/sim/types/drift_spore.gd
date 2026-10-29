extends RefCounted
## A spore that drifts down slowly, swaying left and right ever faster. Touching
## it hurts. When it lands it grows into a hopping sprout.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Sprout = preload("res://src/sim/types/hop_sprout.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e13"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const FIELDS := Body.FIELDS + [["age", 0], ["sway", 48], ["contact", 0]]
const BOX := [-8 * S, -12 * S, 8 * S, 34 * S]
const SWAY_SPEED := 32 * 60
const SWAY_ACCEL := 128
const FALL_ACCEL := 128
const FALL_CAP := 64 * 60
const MAX_AGE := 1_000_000


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


## Seconds between sway turns: 0.8, then 0.6 after 2.3 s and 0.4 after 3.9 s.
static func sway_period(age: int) -> int:
	if age >= 234:
		return 24
	return 36 if age >= 138 else 48


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	entity.age = mini(MAX_AGE, entity.age + 1)
	entity.sway -= 1
	if entity.sway <= 0:
		entity.facing *= -1
		entity.sway = sway_period(entity.age)
	entity.vx = clampi(entity.vx + entity.facing * SWAY_ACCEL, -SWAY_SPEED, SWAY_SPEED)
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		entity.vx = 0
	if Motion.gravity_box(entity, world, BOX, FALL_ACCEL, FALL_CAP):
		grow(entity, state, world)


static func grow(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var registry: Script = load("res://src/sim/registry.gd")
	Body.remove(entity, state)
	registry.spawn_dynamic(
		state,
		world,
		"e12",
		entity.x,
		entity.y + 14 * S,
		{"facing": entity.facing, "mode": Sprout.WAKE, "timer": Sprout.WAKE_TICKS}
	)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var touching := Body.player_overlap(entity, state, BOX)
	if touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state, 1, 1)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": "Left" if entity.facing < 0 else "Right"}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.age >= 0
		and entity.age <= MAX_AGE
		and entity.sway >= 0
		and entity.sway <= 48
		and entity.contact in [0, 1]
	)
