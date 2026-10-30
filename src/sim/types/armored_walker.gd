extends RefCounted
## Walking and jumping armor; impacts roll it, but a stomp does not defeat it.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Moves = preload("res://src/sim/moves.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Birth = preload("res://src/sim/entity_lifecycle.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const Knockback = preload("res://src/sim/knockback.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e11"]
const ENEMY := true
const CREATION_CULL := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const HIT_KIND := Hits.SPIT
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const PREPARE := 1
const AIR := 2
const PUSH := 3
const ROLL := 4
const RECOVER := 5
const COLLECTION_FIELDS := Knockback.COLLECTION_FIELDS
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", WALK],
		["timer", 0],
		["roll_direction", -1],
		["knock_active", 0],
		["birth_frame", 0],
		["birth_serial", 0],
		["birth_phase", Birth.EVENTS_BIRTH]
	]
)
static var _registry: Script = null


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 3)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.mode = AIR if int(source.get("variant", 0)) % 2 == 1 else WALK
	return values


static func bounds(_entity: Dictionary) -> Array:
	return [-14 * S, -14 * S, 14 * S, 16 * S]


## The shared value-tween collection advances once, before any family body moves.
static func before_advance(state: Dictionary, _world: Dictionary) -> void:
	Knockback.advance(state)


static func recreated(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	Knockback.clear(entity)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if (
		Body.process(entity, state) in [Body.HELD, Body.GONE]
		or Body.hazards(entity, state, world, bounds(entity))
	):
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	var box := bounds(entity)
	var grounded := Collision.floor_at(entity, world, box) != 0
	var knocked: bool = entity.knock_active == 1 and not Knockback.deferred(entity)
	var old_vx: int = entity.vx
	match entity.mode:
		ROLL:
			entity.vx = entity.roll_direction * 256 * 60 * entity.timer * entity.timer / 8100
			entity.timer -= 1
		RECOVER:
			entity.vx = 0
			entity.timer -= 1
		PUSH:
			entity.vx = Moves.approach(entity.vx, 0, 256)
			entity.timer -= 1
		PREPARE:
			entity.vx = 0
			entity.timer -= 1
			entity.timer = maxi(entity.timer, 0)
		WALK:
			var wet := int(
				World.water_overlaps(
					world,
					entity.x + box[0],
					entity.y + box[1],
					entity.x + box[2],
					entity.y + box[3]
				)
			)
			entity.vx = entity.facing * 48 * 60 / (wet + 1)
			if entity.variant == 0 and grounded and Motion.edge(entity, world, box):
				entity.facing *= -1
				entity.vx = -entity.vx
		AIR:
			entity.vx = 0
	if knocked:
		entity.vx = old_vx
	var distance: int = entity.vx
	if Motion.move(entity, world, box, distance, true) != distance:
		if entity.mode == WALK:
			entity.facing *= -1
		elif entity.mode == ROLL:
			Body.strike_wall(entity, state, world, box, signi(distance), Hits.SPIT)
	var landed := Motion.gravity_box(entity, world, box)
	if entity.mode == ROLL:
		Body.hit_others(entity, state, world, box, Hits.SPIT)
		if entity.timer == 0:
			entity.mode = RECOVER
			entity.timer = 158 if entity.variant < 2 else 275
	elif entity.mode in [RECOVER, PUSH] and entity.timer == 0:
		entity.mode = AIR if entity.variant % 2 == 1 else WALK
	if entity.mode == PREPARE and entity.timer == 0 and landed:
		# The animation queues a jump; the event launches only when standing.
		entity.mode = AIR
		entity.vy = -536 * 60
	elif entity.variant % 2 == 1 and entity.mode == AIR and landed:
		entity.mode = PREPARE
		entity.timer = 5


## Burst knockback is independent of the jumping animation and its queued jump.
static func knockback(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, from_x: int, _later: bool
) -> void:
	if entity.held or entity.spat or entity.hidden or entity.frozen or entity.status != 1:
		return
	entity.roll_direction = 1 if entity.x > from_x else -1
	Knockback.start(entity, entity.roll_direction * 448 * 60, 60)


static func after_advance(state: Dictionary, world: Dictionary) -> void:
	var first_speed := _first_knock_velocity(state)
	for entity: Dictionary in state.entities:
		if (
			entity.code in CODES
			and entity.status == 1
			and knockback_active(entity)
			and not entity.held
			and not entity.spat
			and not entity.hidden
			and not entity.frozen
		):
			_knock_events(entity, world, first_speed)
			Collision.refresh(world, entity)


## Global99 still picks a naturally completed tween at value zero. Global102
## clears beingKnockedBack only in the late completion trigger, after regular events.
static func knockback_active(entity: Dictionary) -> bool:
	return entity.knock_active == 1


static func after_step(state: Dictionary, _world: Dictionary) -> void:
	for entity: Dictionary in state.entities:
		if entity.code in CODES:
			Knockback.finish(entity)


static func knockback_velocity(entity: Dictionary) -> int:
	return Knockback.value(entity)


static func _first_knock_velocity(state: Dictionary) -> int:
	if _registry == null:
		_registry = load("res://src/sim/registry.gd")
	var first := {}
	var velocity := 0
	for other: Dictionary in state.entities:
		if other.status != 1:
			continue
		var type: Script = _registry.lookup(other.code)
		if not type.has_method("knockback_active") or not type.knockback_active(other):
			continue
		var candidate: int = type.knockback_velocity(other)
		if first.is_empty() or Birth.born_before(other, first):
			first = other
			velocity = candidate
	return velocity


static func _knock_events(entity: Dictionary, world: Dictionary, first_speed: int) -> void:
	entity.vx = knockback_velocity(entity)
	var speed: int = absi(entity.vx)
	var box := bounds(entity)
	# The signed comparison reads the family's first picked body, before the wall
	# condition filters the group. A body can rebound from the wall behind it.
	# The native wall probe tests 2 px sideways, then again 3 px upward.
	# One fixed-point unit includes a wall edge exactly 2 px away.
	var wall_direction := signi(first_speed)
	if (
		absi(first_speed) > 64 * 60
		and Collision.overlaps(entity, world, box, wall_direction * (2 * S + 1), 0)
		and Collision.overlaps(entity, world, box, wall_direction * (2 * S + 1), -3 * S)
	):
		entity.roll_direction = -wall_direction
		entity.facing = entity.roll_direction
		Knockback.stop(entity)
		Knockback.start(entity, entity.roll_direction * 48 * 60, 90)
		speed = 48 * 60
	if speed > 24 * 60 and Collision.floor_at(entity, world, box) != 0:
		entity.vy = -speed / 2 - 160 * 60


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if Body.player_overlap(entity, state, bounds(entity)):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	entity.knock_active = 0
	entity.mode = PUSH
	entity.timer = 30
	entity.vx = state.facing * 128 * 60
	entity.facing = -state.facing
	return 2


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	if kind in [Hits.CLEAR, Hits.SHELL]:
		Body.remove(entity, state)
	elif kind in [Hits.EGG, Hits.SPIT]:
		start_roll(entity, 1 if entity.x > from_x else -1)


static func start_roll(entity: Dictionary, direction: int) -> void:
	entity.knock_active = 0
	entity.mode = ROLL
	entity.timer = 90
	entity.roll_direction = direction
	entity.vx = direction * 256 * 60
	entity.vy = -384 * 60


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if kind == Hits.EGG:
		start_roll(entity, 1 if projectile.vx > 0 else -1)
		return 1
	if kind == Hits.SPIT and projectile.code == "e11":
		Body.remove(entity, state)
	else:
		hit(entity, state, world, kind, projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := ["Walk", "PrepareJump", "Jump", "Pushed", "Hit", "Recover"]
	return {"animation": str(entity.variant / 2) + names[entity.mode]}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= 3
		and entity.mode >= WALK
		and entity.mode <= RECOVER
		and entity.timer >= 0
		and entity.timer <= 275
		and entity.roll_direction in [-1, 1]
		and Knockback.valid(entity)
		and entity.birth_frame >= 0
		and entity.birth_serial >= 0
		and entity.birth_phase in Birth.BIRTH_PHASES
	)
