extends RefCounted
## A ledge-aware walker with a saved wind-up, shot and recoil cycle.

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
const CODES := ["e31"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const PREPARE := 1
const INHALE := 2
const SHOOT := 3
const FIELDS := (
	Body.FIELDS + [["mode", WALK], ["timer", 0], ["cooldown", 0], ["queued", 1], ["contact", 0]]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return [-16 * S, -24 * S, 16 * S, 16 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if Body.process(entity, state) in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	var box := bounds(entity)
	if Body.spit_step(entity, state, world, box) or Body.hazards(entity, state, world, box):
		return
	if entity.cooldown:
		entity.cooldown -= 1
		if entity.cooldown == 0:
			entity.queued = 1
	if entity.mode == WALK:
		if entity.queued:
			entity.queued = 0
			entity.mode = PREPARE
			entity.timer = 15
			entity.vx = 0
		else:
			if entity.cooldown == 0:
				entity.cooldown = 120
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
			if Collision.floor_at(entity, world, box) != 0 and Motion.edge(entity, world, box):
				entity.facing *= -1
				entity.vx = -entity.vx
	else:
		entity.timer -= 1
		if entity.mode == SHOOT:
			entity.vx = Moves.approach(entity.vx, 0, 368)
		if entity.timer == 0:
			if entity.mode == PREPARE:
				entity.mode = INHALE
				entity.timer = 36
			elif entity.mode == INHALE:
				entity.mode = SHOOT
				entity.timer = 35
				entity.vx = -entity.facing * 6072
				var registry: Script = Body.registry_for()
				registry.spawn_dynamic(
					state,
					world,
					"enemy_pellet",
					entity.x + entity.facing * 18 * S,
					entity.y - 8 * S,
					{"facing": entity.facing}
				)
			else:
				entity.mode = WALK
	var distance: int = entity.vx
	if Motion.move(entity, world, box, distance, true) != distance and entity.mode == WALK:
		entity.facing *= -1
	Motion.gravity_box(entity, world, box)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching:
		if entity.y > state.y - 8 * S and not entity.contact:
			if not Body.pounding(state):
				Body.bounce(entity, state, input)
			Body.remove(entity, state)
		elif entity.y < state.y - 8 * S:
			Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	var result := Body.tongue(entity, state)
	if result == 1:
		entity.mode = WALK
		entity.timer = 0
		entity.cooldown = 0
		entity.queued = 1
	return result


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


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {
		"visible": entity.held == 0,
		"animation": ["Walk", "PrepShoot1", "PrepShoot2", "Shoot"][entity.mode]
	}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode >= WALK
		and entity.mode <= SHOOT
		and entity.timer >= 0
		and entity.timer <= 36
		and entity.cooldown >= 0
		and entity.cooldown <= 120
		and entity.queued in [0, 1]
		and entity.contact in [0, 1]
	)
