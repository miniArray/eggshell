extends RefCounted
## A small biting sprout that hops along the ground, turning at walls. Grown from
## a landed spore, it first wakes for a moment and turns to face the player.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e12"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const HOP := 0
const WAKE := 1
const WAKE_TICKS := 15  # Two frames at 8 per second.
const HOP_DELAY := 3  # 0.05 s on the ground between hops.
const FIELDS := Body.FIELDS + [["mode", HOP], ["timer", 0], ["contact", 0]]
const BOX := [-12 * S, -14 * S, 12 * S, 16 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	if entity.mode == WAKE:
		entity.timer -= 1
		if entity.timer <= 0:
			entity.mode = HOP
			entity.timer = 0
			entity.facing = 1 if state.x > entity.x else -1
		Motion.gravity_box(entity, world, BOX)
		return
	var grounded: bool = Collision.floor_at(entity, world, BOX) != 0 and entity.vy >= 0
	if grounded:
		entity.vx = 0
		if entity.timer == 0:
			entity.timer = HOP_DELAY
		else:
			entity.timer -= 1
			if entity.timer == 0:
				entity.vy = -256 * 60
				entity.vx = entity.facing * 64 * 60
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		entity.facing *= -1
		entity.vx = -entity.vx
	if Motion.gravity_box(entity, world, BOX):
		entity.vx = 0


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and not entity.contact and entity.y > state.y - 8 * S:
		if not Body.pounding(state):
			Moves.bounce(state, -absi(entity.vy / 2) - 320 * 60, input)
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
	if entity.mode == WAKE:
		return {"visible": entity.held == 0, "animation": "Wake"}
	return {
		"visible": entity.held == 0,
		"animation": "Hop",
		"frame": 0 if entity.vy == 0 else (1 if entity.vy < 0 else 2)
	}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode in [HOP, WAKE]
		and entity.timer >= 0
		and entity.timer <= WAKE_TICKS
		and entity.contact in [0, 1]
	)
