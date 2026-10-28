extends RefCounted
## A large soft walker. A plain landing bounces the player and stalls it; a ground
## pound squashes it under the player and then bursts it into four small walkers.
## Thrown eggs and objects shove it sideways instead of defeating it.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const Small = preload("res://src/sim/types/soft_walker.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e24"]
const ENEMY := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WAIT := 0
const WALK := 1
const PAUSE := 2
const SQUASH := 3
const WAIT_TICKS := 5  # 0.075 s before walking resumes.
const PAUSE_TICKS := 30  # 0.5 s stall after a plain landing.
const SQUASH_TICKS := 15  # 0.25 s to half height.
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", WAIT],
		["timer", WAIT_TICKS],
		["contact", 0],
		["pin_dx", 0],
		["slide_from", 0],
		["slide_to", 0],
		["slide_ticks", 0],
		["slide_total", 0]
	]
)
const BOX := [-24 * S, -56 * S, 24 * S, 0]
## Burst copies: offset from the feet at half height, speed and launch velocity.
const COPIES := [
	[-32, -16, -320, -416], [-16, -32, -256, -480], [16, -32, 256, -480], [32, -16, 320, -416]
]
const MAX_SLIDE := 1024 * 60


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var result := Options.prepare(source, 0)
	if result.ok:
		source.y += 32 * S  # The body stands on the placement's lower edge.
	return result


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return BOX


## Drawn height in pixels; the squash halves it.
static func height(entity: Dictionary) -> int:
	if entity.mode != SQUASH:
		return 64
	return 64 - 32 * (SQUASH_TICKS - entity.timer) / SQUASH_TICKS


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Body.hazards(entity, state, world, BOX):
		return
	if entity.mode == SQUASH:
		entity.vx = 0
		entity.timer -= 1
		pin(entity, state)
		if entity.timer <= 0:
			burst(entity, state, world)
		return
	if entity.mode in [WAIT, PAUSE]:
		entity.timer -= 1
		if entity.timer <= 0:
			entity.mode = WALK if entity.mode == WAIT else WAIT
			entity.timer = WAIT_TICKS if entity.mode == WAIT else 0
	var grounded := Collision.floor_at(entity, world, BOX) != 0
	if entity.slide_ticks > 0:
		var done: int = entity.slide_total - entity.slide_ticks
		entity.vx = (
			entity.slide_from + (entity.slide_to - entity.slide_from) * done / entity.slide_total
		)
		entity.slide_ticks -= 1
	elif entity.mode == WALK:
		var wet := int(
			World.water_overlaps(
				world, entity.x + BOX[0], entity.y + BOX[1], entity.x + BOX[2], entity.y + BOX[3]
			)
		)
		entity.vx = entity.facing * 48 * 60 / (wet + 1)
		if grounded and Motion.edge(entity, world, BOX):
			entity.facing *= -1
			entity.vx = -entity.vx
	else:
		entity.vx = 0
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, BOX, distance, true) != distance:
		entity.facing *= -1
		entity.slide_from = -entity.slide_from
		entity.slide_to = -entity.slide_to
	Motion.gravity_box(entity, world, BOX)


static func pin(entity: Dictionary, state: Dictionary) -> void:
	state.x = entity.x + entity.pin_dx
	state.y = entity.y - (height(entity) - 4) * S
	state.vx = 0
	state.vy = 0
	state.on_floor = 1


static func burst(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var registry: Script = load("res://src/sim/registry.gd")
	Body.remove(entity, state)
	for copy: Array in COPIES:
		registry.spawn_dynamic(
			state,
			world,
			"e23",
			entity.x + copy[0] * S,
			entity.y + copy[1] * S,
			Small.tumble_options(signi(copy[2]), copy[2] * 60, copy[3] * 60, 30)
		)


static func shove(entity: Dictionary, direction: int, ticks: int) -> void:
	entity.slide_from = direction * 512 * 60
	entity.slide_to = direction * 384 * 60
	entity.slide_ticks = ticks
	entity.slide_total = ticks


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if entity.mode == SQUASH:
		return
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and not entity.contact and entity.y > state.y + 24 * S:
		if Body.pounding(state):
			entity.mode = SQUASH
			entity.timer = SQUASH_TICKS
			entity.vx = 0
			entity.slide_ticks = 0
			entity.pin_dx = clampi(state.x - entity.x, -32 * S, 32 * S)
			pin(entity, state)
		else:
			Moves.bounce(state, -absi(entity.vy / 2) - 336 * 60, input)
			entity.mode = PAUSE
			entity.timer = PAUSE_TICKS
			entity.vx = 0
	elif touching and entity.y < state.y + 24 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, _kind: int, from_x: int
) -> void:
	if entity.mode != SQUASH:
		shove(entity, 1 if from_x < entity.x else -1, 6)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	if entity.mode == SQUASH:
		return 0
	var direction := 1 if projectile.x < entity.x else -1
	if Body.projectile_kind(projectile) == Hits.EGG:
		var travel: int = projectile.get("vx", 0)
		shove(entity, signi(travel) if travel else direction, 48)
		return 1
	shove(entity, direction, 6)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.held == 0, "animation": "Walk", "size_y": float(height(entity))}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode in [WAIT, WALK, PAUSE, SQUASH]
		and entity.timer >= 0
		and entity.timer <= PAUSE_TICKS
		and entity.contact in [0, 1]
		and absi(entity.pin_dx) <= 32 * S
		and absi(entity.slide_from) <= MAX_SLIDE
		and absi(entity.slide_to) <= MAX_SLIDE
		and entity.slide_total >= 0
		and entity.slide_total <= 600
		and entity.slide_ticks >= 0
		and entity.slide_ticks <= entity.slide_total
	)
