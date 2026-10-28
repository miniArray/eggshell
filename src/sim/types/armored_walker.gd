extends RefCounted
## Walking and jumping armor; impacts roll it, but a stomp does not defeat it.

const Body = preload("res://src/sim/enemy_body.gd")
const Moves = preload("res://src/sim/moves.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e11"]
const ENEMY := true
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
const FIELDS := Body.FIELDS + [["mode", WALK], ["timer", 0], ["roll_direction", -1]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 3)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.mode = AIR if int(source.get("variant", 0)) % 2 == 1 else WALK
	return values


static func bounds(_entity: Dictionary) -> Array:
	return [-14 * S, -14 * S, 14 * S, 16 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if (
		Body.process(entity, state) in [Body.HELD, Body.GONE]
		or Body.hazards(entity, state, world, bounds(entity))
	):
		return
	var box := bounds(entity)
	var grounded := Collision.floor_at(entity, world, box) != 0
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
			if entity.timer == 0:
				entity.mode = AIR
				entity.vy = -536 * 60
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
	if entity.variant % 2 == 1 and entity.mode == AIR and landed:
		entity.mode = PREPARE
		entity.timer = 5


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if Body.player_overlap(entity, state, bounds(entity)):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	entity.mode = PUSH
	entity.timer = 30
	entity.vx = state.facing * 128 * 60
	entity.facing = -state.facing
	return 2


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, from_x: int
) -> void:
	if kind in [Hits.CLEAR, Hits.SHELL]:
		Body.remove(entity, state)
	elif kind in [Hits.EGG, Hits.SPIT]:
		start_roll(entity, 1 if entity.x > from_x else -1)


static func start_roll(entity: Dictionary, direction: int) -> void:
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
	)
