extends RefCounted
## A small walker that flattens into a moving, top-only support.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Moves = preload("res://src/sim/moves.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e4"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const SOLID := 2
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const PREPARE := 1
const AIR := 2
const IDLE := 3
const FLATTEN := 4
const FLAT := 5
const RECOVER := 6
const FIELDS := Body.FIELDS + [["mode", WALK], ["timer", 0], ["flat_wait", 360], ["contact", 0]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(entity: Dictionary) -> Array:
	return (
		[-14 * S, 2 * S, 14 * S, 16 * S]
		if entity.mode >= FLATTEN
		else [-12 * S, -14 * S, 12 * S, 16 * S]
	)


static func solid_box(entity: Dictionary) -> Array:
	return (
		Body.world_box(entity, bounds(entity))
		if entity.mode >= FLATTEN and not entity.held and not entity.spat
		else []
	)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	var box := bounds(entity)
	if Body.spit_step(entity, state, world, box) or Body.hazards(entity, state, world, box):
		return
	var grounded := Collision.floor_at(entity, world, box) != 0
	# Only a fall lands: settling onto the floor at the placement is not a landing.
	var falling: bool = entity.vy > 0
	var leaping := false
	if entity.mode in [PREPARE, IDLE, FLATTEN, RECOVER]:
		entity.vx = 0
		entity.timer = maxi(0, entity.timer - 1)
		if entity.timer == 0:
			match entity.mode:
				PREPARE:
					entity.mode = AIR
					entity.vy = -384 * 60
					leaping = true
				IDLE, RECOVER:
					entity.mode = WALK
				FLATTEN:
					entity.mode = FLAT
					entity.flat_wait = 360
	if entity.mode in [WALK, AIR, FLAT]:
		var wet := int(
			World.water_overlaps(
				world, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
			)
		)
		entity.vx = entity.facing * 48 * 60 / (wet + 1)
		# The leap leaves the ledge walking; only a body that stood on the floor
		# before this step can stop at its edge again.
		if grounded and not leaping and Motion.edge(entity, world, box):
			if entity.mode == FLAT:
				entity.facing *= -1
				entity.vx = -entity.vx
			else:
				entity.mode = PREPARE
				entity.timer = 45
				entity.vx = 0
		var distance: int = entity.vx
		if Motion.move(entity, world, box, distance, true) != distance:
			entity.facing *= -1
	var landed := Motion.gravity_box(entity, world, box)
	if landed and not grounded and falling and entity.mode < FLATTEN:
		entity.mode = IDLE
		entity.timer = 60
		entity.vx = 0
	if entity.mode == FLAT:
		var support_box := Body.world_box(entity, box)
		support_box[1] -= 4 * S
		support_box[3] -= 4 * S
		if Body.overlap(support_box, Body.world_box(state, Moves.player_box(state))):
			entity.flat_wait = 360
		else:
			entity.flat_wait = maxi(0, entity.flat_wait - 1)
		if entity.flat_wait == 0:
			entity.mode = RECOVER
			entity.timer = 65


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if Body.impact_on_top(entity, state, bounds(entity)):
		Body.remove(entity, state)
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching:
		if entity.y > state.y - 8 * S and not entity.contact:
			if Body.pounding(state):
				Body.remove(entity, state)
			else:
				if entity.mode < FLATTEN:
					Body.bounce(entity, state, input)
				entity.timer = 63 if entity.mode == FLAT else 65
				entity.mode = FLATTEN
				entity.vx = 0
		elif entity.mode < FLATTEN and entity.y < state.y - 8 * S:
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
	var kind := Body.projectile_kind(projectile)
	if kind == Hits.EGG:
		projectile.fall_on_terrain = 1
	hit(entity, state, world, kind, projectile.x)
	return 3


static func bump(entity: Dictionary, state: Dictionary, world: Dictionary, side: int) -> void:
	if side == 1:
		hit(entity, state, world, Hits.POUND, state.x)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var names := ["Walk", "PrepareJump", "Jump", "Idle", "Squash", "SquashWalk", "Unsquash"]
	return {
		"visible": entity.held == 0,
		"animation": "Fall" if entity.mode == AIR and entity.vy >= 0 else names[entity.mode]
	}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode >= WALK
		and entity.mode <= RECOVER
		and entity.timer >= 0
		and entity.timer <= 65
		and entity.flat_wait >= 0
		and entity.flat_wait <= 360
		and entity.contact in [0, 1]
	)
