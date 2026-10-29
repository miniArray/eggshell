extends RefCounted
## A walker that conjures a spiked ball and hurls it at a level player. An egg sets it
## rolling away; a rolling walker breaks on walls and on the player.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e27"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const CONJURE := 1
const AIM := 2
const THROW := 3
const ROLL := 4
const LOFT := 5
const CONJURE_TICKS := 45
const AIM_TICKS := 24
const COOLDOWN := 120
const ROLL_GRACE := 15
const WALK_BOX := [-14 * S, -14 * S, 14 * S, 16 * S]
const ROLL_BOX := [-14 * S, -12 * S, 14 * S, 16 * S]
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", WALK],
		["throw_tick", 0],
		["aim", 1],
		["ball_token", 0],
		["cooldown", 0],
		["grace", 0],
		["bounced", 0],
		["grounded", 1],
		["contact", 0]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(entity: Dictionary) -> Array:
	return ROLL_BOX if entity.mode == ROLL else WALK_BOX


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action == Body.HELD:
		_drop_ball(entity, state)
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if action == Body.GONE:
		return
	if action == Body.RELEASED:
		entity.spat = 0
		var direction: int = state.facing if state.facing != 0 else 1
		if entity.vx == 0:
			# Spat upward: a high arc that knocks over what it meets.
			entity.mode = LOFT
			entity.facing = direction
			entity.vx = direction * (256 * 60 + absi(state.vx))
			entity.vy = -768 * 60
			entity.grounded = 0
		else:
			roll(entity, state, direction, -256 * 60)
	if Body.hazards(entity, state, world, bounds(entity)):
		return
	entity.cooldown = maxi(0, entity.cooldown - 1)
	entity.grace = maxi(0, entity.grace - 1)
	match entity.mode:
		WALK:
			_walk(entity, state, world)
		CONJURE, AIM:
			entity.vx = 0
			entity.throw_tick += 1
			if entity.throw_tick == CONJURE_TICKS:
				entity.mode = AIM
			elif entity.throw_tick >= CONJURE_TICKS + AIM_TICKS:
				_throw(entity, state)
		THROW, LOFT:
			pass
		ROLL:
			entity.vx = entity.facing * 432 * 60
	var box := bounds(entity)
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, box, distance, true) != distance:
		if entity.mode == ROLL:
			Body.remove(entity, state)
			return
		if entity.mode == WALK:
			entity.facing *= -1
		entity.vx = 0
	var landed := Motion.gravity_box(entity, world, box)
	if landed and not entity.grounded:
		if entity.mode == THROW:
			entity.mode = WALK
			entity.cooldown = COOLDOWN
		elif entity.mode == LOFT:
			entity.mode = WALK
			entity.vx = 0
		elif entity.mode == ROLL and not entity.bounced:
			entity.vy = -384 * 60
			entity.bounced = 1
			landed = false
	entity.grounded = int(landed or Collision.floor_at(entity, world, box) != 0)
	if entity.mode in [ROLL, LOFT] and entity.status == 1:
		Body.hit_others(entity, state, world, box, Hits.SHELL)


static func _walk(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var wet := int(
		World.water_overlaps(
			world,
			entity.x + WALK_BOX[0],
			entity.y + WALK_BOX[1],
			entity.x + WALK_BOX[2],
			entity.y + WALK_BOX[3]
		)
	)
	entity.vx = entity.facing * 48 * 60 / (wet + 1)
	if entity.grounded and Motion.edge(entity, world, WALK_BOX):
		entity.facing *= -1
		entity.vx = -entity.vx
	var facing_player: bool = (
		(entity.facing < 0 and entity.x > state.x) or (entity.facing > 0 and entity.x < state.x)
	)
	if (
		entity.cooldown == 0
		and facing_player
		and entity.y < state.y + 64 * S
		and entity.y > state.y - 116 * S
		and not state.get("captured_by", 0)
	):
		_conjure(entity, state, world)


static func _conjure(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.mode = CONJURE
	entity.vx = 0
	entity.throw_tick = 0
	entity.aim = -entity.facing
	var ball: Dictionary = Body.registry_for().spawn_dynamic(
		state,
		world,
		"enemy_mace",
		entity.x - 4 * S * entity.aim,
		entity.y - 2 * S,
		{"owner_token": entity.token, "aim": entity.aim, "can_despawn": 1}
	)
	entity.ball_token = ball.get("token", 0)


static func ball(entity: Dictionary, state: Dictionary) -> Dictionary:
	if not entity.ball_token:
		return {}
	var found: Dictionary = Body.registry_for().find_token(state, entity.ball_token)
	if found.is_empty() or found.status != 1 or found.get("owner_token", 0) != entity.token:
		return {}
	return found


static func _throw(entity: Dictionary, state: Dictionary) -> void:
	var held := ball(entity, state)
	if not held.is_empty():
		held.mode = 1
		held.owner_token = 0
		held.lift = 12
	entity.ball_token = 0
	entity.mode = THROW
	entity.vy = -192 * 60
	entity.vx = 48 * 60 * entity.aim
	entity.grounded = 0


static func _drop_ball(entity: Dictionary, state: Dictionary) -> void:
	var held := ball(entity, state)
	if not held.is_empty():
		held.mode = 2
		held.owner_token = 0
		held.vx = 0
		held.vy = 0
	entity.ball_token = 0


static func roll(entity: Dictionary, state: Dictionary, direction: int, vy: int) -> void:
	_drop_ball(entity, state)
	entity.mode = ROLL
	entity.facing = direction
	entity.vx = direction * 432 * 60
	entity.vy = vy
	entity.grace = ROLL_GRACE
	entity.grounded = 0


static func on_remove(entity: Dictionary, state: Dictionary) -> void:
	_drop_ball(entity, state)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var box := bounds(entity)
	var touching := Body.player_overlap(entity, state, box)
	if entity.mode in [ROLL, LOFT]:
		if touching and entity.mode == ROLL and entity.grace == 0:
			Body.remove(entity, state)
	elif touching and entity.y > state.y - 8 * S:
		if not entity.contact:
			if not Body.pounding(state):
				Body.bounce(entity, state, input)
			Body.remove(entity, state)
	elif touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state, 1)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if kind != Hits.EGG:
		hit(entity, state, world, kind, projectile.get("x", entity.x))
		return 3
	# The egg is used up and sends the walker rolling away from it.
	var from: int = projectile.get("x", entity.x)
	roll(entity, state, 1 if entity.x > from else -1, 0)
	return 1


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := ["Walk", "CreateSpikeball", "PrepareThrow", "Throw", "Roll", "Walk"]
	return {"visible": entity.held == 0, "animation": names[entity.mode]}


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode >= WALK
		and entity.mode <= LOFT
		and entity.throw_tick >= 0
		and entity.throw_tick <= CONJURE_TICKS + AIM_TICKS
		and entity.aim in [-1, 1]
		and entity.ball_token >= 0
		and entity.cooldown >= 0
		and entity.cooldown <= COOLDOWN
		and entity.grace >= 0
		and entity.grace <= ROLL_GRACE
		and entity.bounced in [0, 1]
		and entity.grounded in [0, 1]
		and entity.contact in [0, 1]
	)
