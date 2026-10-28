extends RefCounted
## Burn and freeze reactions shared by enemy types.
##
## A type opts in with an `ELEMENT_REACTIONS` constant built from the flags in
## `elements.gd`. Its `hit` hook passes fire and ice strikes here first. While
## the body is frozen its `step` and `contact` hooks call `frozen_step` and
## `frozen_contact` before their own logic. A frozen body stops, falls unless
## anchored, can still be eaten and spat, and shatters when the player touches
## it; a stomp from above also bounces the player.

const Elements = preload("res://src/sim/elements.gd")
const Hits = preload("res://src/sim/hits.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const S := preload("res://src/sim/units.gd").SCALE
## A body hops up when it freezes on the ground and when it thaws.
const HOP := -384 * 60


static func is_element(kind: int) -> bool:
	return kind == Hits.FIRE or kind == Hits.ICE


## Applies a fire or ice strike. Returns true when `kind` was an element strike,
## so the caller's own hit logic must not run.
static func hit(
	entity: Dictionary,
	state: Dictionary,
	world: Dictionary,
	kind: int,
	reactions: int,
	bounds: Array
) -> bool:
	if not is_element(kind):
		return false
	if entity.status != 1 or entity.get("held", 0):
		return true
	if kind == Hits.FIRE and reactions & Elements.BURNS:
		burn(entity, state)
	elif kind == Hits.ICE and reactions & Elements.FREEZES and not entity.get("frozen", 0):
		freeze(entity, world, reactions, bounds)
	return true


## Fire defeats the body at once; nothing touches a burning body again.
static func burn(entity: Dictionary, state: Dictionary) -> void:
	Body.remove(entity, state)


static func freeze(entity: Dictionary, world: Dictionary, reactions: int, bounds: Array) -> void:
	entity.frozen = 1
	entity.thaw_ticks = Elements.THAW_TICKS if reactions & Elements.THAWS else 0
	entity.vx = 0
	if not reactions & Elements.ANCHORED and bounds.size() == 4:
		entity.vy = HOP if Collision.floor_at(entity, world, bounds) != 0 else 0


## The frozen body's whole step. Returns false when the body is not frozen.
static func frozen_step(
	entity: Dictionary, state: Dictionary, world: Dictionary, bounds: Array, reactions: int
) -> bool:
	if not entity.get("frozen", 0):
		return false
	if entity.held or entity.spat:
		return false
	if entity.thaw_ticks > 0:
		entity.thaw_ticks -= 1
		if entity.thaw_ticks == 0:
			entity.frozen = 0
			entity.vy = HOP
			return true
	entity.vx = 0
	if not reactions & Elements.ANCHORED:
		Motion.gravity_box(entity, world, bounds)
	Body.hazards(entity, state, world, bounds)
	return true


## The frozen body's whole player contact. Returns false when it is not frozen.
static func frozen_contact(
	entity: Dictionary, state: Dictionary, input: int, bounds: Array
) -> bool:
	if not entity.get("frozen", 0):
		return false
	if Body.player_overlap(entity, state, bounds):
		if entity.y > state.y - 8 * S and not Body.pounding(state):
			Body.bounce(entity, state, input)
		shatter(entity, state)
	return true


static func shatter(entity: Dictionary, state: Dictionary) -> void:
	Body.remove(entity, state)


## True during the last second before a thaw, when the ice shakes.
static func shaking(entity: Dictionary) -> bool:
	return (
		entity.get("frozen", 0) == 1
		and entity.get("thaw_ticks", 0) > 0
		and entity.thaw_ticks <= Elements.SHAKE_TICKS
	)


static func valid(entity: Dictionary) -> bool:
	return (
		entity.get("frozen", 0) in [0, 1]
		and entity.get("thaw_ticks", 0) >= 0
		and entity.get("thaw_ticks", 0) <= Elements.THAW_TICKS
		and (entity.get("frozen", 0) == 1 or entity.get("thaw_ticks", 0) == 0)
	)
