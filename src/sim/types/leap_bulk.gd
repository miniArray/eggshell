extends RefCounted
## A heavy leaper with a top-only deck. It waits a second on the ground, crouches,
## and leaps forward, turning at walls; it holds still while the player stands on
## it. A ground pound on its deck, a thrown egg or a thrown body defeats it and
## releases its reward.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e17"]
const ENEMY := true
const GOAL_COIN := true
const SOLID := 2
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WAIT := 0
const FLATTEN := 1
const RISE := 2
const AIR := 3
const WAIT_TICKS := 60  # 1 s on the ground.
const FLATTEN_TICKS := 12  # 0.2 s crouch.
const RISE_TICKS := 6  # 0.1 s back up before leaving the ground.
const FIELDS := Body.FIELDS + [["phase", WAIT], ["timer", 0], ["squashed", 0], ["contact", 0]]
const BOX := [-18 * S, -28 * S, 18 * S, 16 * S]
const DECK_TOP := -26 * S


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 2)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or entity.held or entity.spat:
		return []
	var top: int = entity.y + DECK_TOP
	return [entity.x - 17 * S, top, entity.x + 17 * S, top + 2 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Body.spit_step(entity, state, world, BOX) or Body.hazards(entity, state, world, BOX):
		return
	match entity.phase:
		WAIT:
			entity.vx = 0
			var grounded := Collision.floor_at(entity, world, BOX) != 0
			if grounded and not entity.squashed:
				entity.timer += 1
				if entity.timer >= WAIT_TICKS:
					entity.phase = FLATTEN
					entity.timer = FLATTEN_TICKS
		FLATTEN, RISE:
			entity.timer -= 1
			if entity.timer <= 0:
				if entity.phase == FLATTEN:
					entity.phase = RISE
					entity.timer = RISE_TICKS
				else:
					entity.phase = AIR
					entity.timer = 0
					entity.vy = -768 * 60
		AIR:
			var wet := int(
				World.water_overlaps(
					world,
					entity.x + BOX[0],
					entity.y + BOX[1],
					entity.x + BOX[2],
					entity.y + BOX[3]
				)
			)
			entity.vx = entity.facing * 206 * 60 / (wet + 1)
			var distance: int = entity.vx
			if Motion.move(entity, world, BOX, distance, true) != distance:
				entity.facing *= -1
	if Motion.gravity_box(entity, world, BOX) and entity.phase == AIR:
		entity.phase = WAIT
		entity.timer = 0
		entity.vx = 0


static func standing(entity: Dictionary, state: Dictionary) -> bool:
	var box := Moves.player_box(state)
	var feet: int = state.y + box[3]
	var top: int = entity.y + DECK_TOP
	return (
		state.x + box[2] >= entity.x - 17 * S
		and state.x + box[0] <= entity.x + 17 * S
		and feet <= top + 4 * S
		and feet + 4 * S >= top
	)


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, _input: int) -> void:
	var on_deck := standing(entity, state)
	if on_deck and Body.pounding(state):
		defeat(entity, state, world)
		return
	entity.squashed = int(on_deck and state.on_floor)
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and not on_deck and entity.y < state.y - 8 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func defeat(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.status != 1:
		return
	var registry: Script = load("res://src/sim/registry.gd")
	for index in 3:
		if entity.variant == 1 or (entity.variant == 2 and state.health + index >= 30):
			registry.spawn_dynamic(
				state,
				world,
				"o1",
				entity.x,
				entity.y,
				{
					"moving": 1,
					"despawn_ticks": 480,
					"pickup_delay": 30,
					"vx": Motion.random_ticks(state, -256 * 60, 256 * 60),
					"vy": -Motion.random_ticks(state, 256 * 60, 384 * 60)
				}
			)
		elif entity.variant == 2:
			registry.spawn_dynamic(
				state,
				world,
				"o4",
				entity.x,
				entity.y,
				{
					"vy": -Motion.random_ticks(state, 256 * 60, 512 * 60),
					"facing": -1 if Motion.random_ticks(state, 0, 1) == 0 else 1,
					"despawn_ticks": 480,
					"max_speed": Motion.random_ticks(state, 64 * 60, 128 * 60)
				}
			)
	Body.remove(entity, state)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, _kind: int, _from_x: int
) -> void:
	defeat(entity, state, world)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	defeat(entity, state, world)
	return 1 if kind in [Hits.EGG, Hits.SPIT] and projectile.code == "o7" else 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var result := {"visible": entity.held == 0}
	if entity.phase == FLATTEN or entity.squashed:
		result.size_y = 32.0
	return result


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= 2
		and entity.phase in [WAIT, FLATTEN, RISE, AIR]
		and entity.timer >= 0
		and entity.timer <= WAIT_TICKS
		and entity.squashed in [0, 1]
		and entity.contact in [0, 1]
	)
