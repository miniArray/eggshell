extends RefCounted
## A launcher's shot. It flies through terrain in a straight line; the bouncing
## form instead pauses on touching a solid and then reflects off it; the homing
## form turns toward the player, slowing while it turns. Landing on a
## shot stops it and it drops away. It can be eaten.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["enemy_shot"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES | Elements.THAWS
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const STRAIGHT := 0
const BOUNCE := 1
const HOMING := 2
const FIELDS := (
	Body.FIELDS
	+ [
		["form", STRAIGHT],
		["heading", 0],
		["pause", 0],
		["fresh", 1],
		["falling", 0],
		["contact", 0]
	]
)
const BOX := [-17 * S, -22 * S, 17 * S, 22 * S]
const PAUSE_TICKS := 15  # 0.25 s held against a solid before reflecting.
const GRAVITY := 1024
const FALL_CAP := 704 * 60
const PROBE := S / 2


static func prepare(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.can_respawn = 0
	return values


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if action == Body.RELEASED:
		entity.spat = 0
		entity.falling = 0
		entity.heading = 0 if entity.facing > 0 else 180000
	if entity.falling:
		entity.vy = mini(FALL_CAP, entity.vy + GRAVITY)
		entity.y += entity.vy
		return
	if entity.form == BOUNCE:
		if entity.fresh and Collision.overlaps(entity, world, BOX):
			Body.remove(entity, state)
			return
		entity.fresh = 0
		if entity.pause:
			entity.pause -= 1
			if entity.pause == 0:
				reflect(entity, world)
			else:
				return
		elif touching(entity, world):
			entity.pause = PAUSE_TICKS
			return
	entity.fresh = 0
	if entity.form == HOMING:
		home(entity, state)
	entity.x += entity.vx
	entity.y += entity.vy


## Turn toward a point 32 px above the player by up to 0.1° + distance/140 px per
## tick; speed drops by 40 px/s per unit of turn (the turn's diagonal distance).
static func home(entity: Dictionary, state: Dictionary) -> void:
	var dx: int = state.x - entity.x
	var dy: int = state.y - 32 * S - entity.y
	var distance: int = Motion.root(dx / S * (dx / S) + dy / S * (dy / S))
	var limit: int = 100 + distance * 1000 / 140
	var turn: int = clampi(
		Motion.angle_delta(entity.heading, Motion.angle_to(dx, dy)), -limit, limit
	)
	entity.heading = posmod(entity.heading + turn, 360000)
	var throttle: int = absi(turn) * 1414 / 1000  # Millidegrees of diagonal turn.
	var speed: int = 296 * 60
	if throttle <= 45000:
		speed = (296000 - 40 * throttle) * 60 / 1000
	entity.vx = speed * Motion.turn_cosine(entity.heading) / S
	entity.vy = speed * Motion.turn_sine(entity.heading) / S


static func touching(entity: Dictionary, world: Dictionary) -> bool:
	for offset: Array in [[-PROBE, 0], [PROBE, 0], [0, -PROBE], [0, PROBE]]:
		if Collision.overlaps(entity, world, BOX, offset[0], offset[1]):
			return true
	return false


## Reflect the component that points into the solid the shot is touching.
static func reflect(entity: Dictionary, world: Dictionary) -> void:
	var dx := signi(entity.vx)
	var dy := signi(entity.vy)
	if dx and Collision.overlaps(entity, world, BOX, dx * PROBE, 0):
		entity.vx = -entity.vx
	if dy and Collision.overlaps(entity, world, BOX, 0, dy * PROBE):
		entity.vy = -entity.vy
	if entity.vx or entity.vy:
		entity.heading = Motion.angle_to(entity.vx, entity.vy)
	entity.facing = 1 if entity.vx >= 0 else -1


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if entity.falling:
		entity.contact = 0
		return
	var touching_player := Body.player_overlap(entity, state, BOX)
	if touching_player and not entity.contact and entity.y > state.y - 8 * S:
		Moves.bounce(state, -320 * 60, input)
		entity.falling = 1
		entity.vx = 0
		entity.vy = 0
	elif touching_player and entity.y < state.y - 8 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching_player)


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
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.held == 0,
		"animation": "Bounce" if entity.pause else str(entity.form),
		"rotation": float(entity.heading) / 1000.0
	}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.form in [STRAIGHT, BOUNCE, HOMING]
		and entity.heading >= 0
		and entity.heading < 360000
		and entity.pause >= 0
		and entity.pause <= PAUSE_TICKS
		and entity.fresh in [0, 1]
		and entity.falling in [0, 1]
		and entity.contact in [0, 1]
	)
