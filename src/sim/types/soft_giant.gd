extends RefCounted
## A large soft walker. A plain landing bounces the player and stalls it; a ground
## pound squashes it under the player and then bursts it into four small walkers.
## Thrown eggs and objects shove it sideways instead of defeating it.

const Body = preload("res://src/sim/enemy_body.gd")
const Birth = preload("res://src/sim/entity_lifecycle.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
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
const DYNAMIC := true
const ELEMENT_REACTIONS := Elements.FREEZES
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
## Latest allocated start batch; nonzero ordinal means its starts await a pretick drain.
const LEVEL_FIELDS := [["soft_squash_batch", 0], ["soft_squash_ordinal", 0]]
const MAX_SCHEDULE := 0x7ffffffffffffffe
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
		["slide_total", 0],
		["squash_batch", 0],
		["squash_ordinal", 0]
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
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	if Body.hazards(entity, state, world, BOX):
		return
	if entity.mode == SQUASH:
		entity.vx = 0
		entity.timer = maxi(0, entity.timer - 1)
		pin(entity, state)
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


## TimelineManager drains pending starts at the next pretick, not at a birth/frame
## boundary. The next registration opens a new batch, even within begin_level's frame 0.
static func before_advance(state: Dictionary, _world: Dictionary) -> void:
	state.soft_squash_ordinal = 0


## ScheduleTimeline pushes; pretick pops into playing, then ticks playing backwards.
## Tick2 dispatches the removal queue forwards: newer batches first, each in start order.
## Timer zero is the saved natural-completion queue; the parent stays pinned until here.
static func after_step(state: Dictionary, world: Dictionary) -> void:
	var pending := []
	for entity: Dictionary in state.entities:
		if (
			entity.code in CODES
			and entity.status == Birth.ACTIVE
			and entity.mode == SQUASH
			and entity.timer == 0
		):
			pending.append(entity)
	pending.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.squash_batch != b.squash_batch:
				return a.squash_batch > b.squash_batch
			return a.squash_ordinal < b.squash_ordinal
	)
	for entity: Dictionary in pending:
		burst(entity, state, world)


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
			Small.tumble_options(signi(copy[2]), copy[2] * 60, copy[3] * 60, 30),
			Birth.TICK2_BIRTH
		)


static func shove(entity: Dictionary, direction: int, ticks: int) -> void:
	entity.slide_from = direction * 512 * 60
	entity.slide_to = direction * 384 * 60
	entity.slide_ticks = ticks
	entity.slide_total = ticks


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if entity.mode == SQUASH:
		pin(entity, state)
		return
	var touching := Body.player_overlap(entity, state, BOX)
	if touching and not entity.contact and entity.y > state.y + 24 * S:
		if Body.pounding(state):
			if (
				state.soft_squash_ordinal == MAX_SCHEDULE
				or (state.soft_squash_ordinal == 0 and state.soft_squash_batch == MAX_SCHEDULE)
			):
				push_warning("Large soft squash scheduling is exhausted")
				return
			if state.soft_squash_ordinal == 0:
				state.soft_squash_batch += 1
			state.soft_squash_ordinal += 1
			entity.squash_batch = state.soft_squash_batch
			entity.squash_ordinal = state.soft_squash_ordinal
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
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
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
		and entity.timer <= (SQUASH_TICKS if entity.mode == SQUASH else PAUSE_TICKS)
		and entity.squash_batch >= 0
		and entity.squash_batch <= MAX_SCHEDULE
		and entity.squash_ordinal >= 0
		and entity.squash_ordinal <= MAX_SCHEDULE
		and ((entity.squash_batch > 0 and entity.squash_ordinal > 0) == (entity.mode == SQUASH))
		and ((entity.squash_batch == 0) == (entity.squash_ordinal == 0))
		and entity.contact in [0, 1]
		and absi(entity.pin_dx) <= 32 * S
		and absi(entity.slide_from) <= MAX_SLIDE
		and absi(entity.slide_to) <= MAX_SLIDE
		and entity.slide_total >= 0
		and entity.slide_total <= 600
		and entity.slide_ticks >= 0
		and entity.slide_ticks <= entity.slide_total
	)


static func valid_state(state: Dictionary) -> bool:
	for key: String in ["soft_squash_batch", "soft_squash_ordinal"]:
		if not state.get(key) is int or state[key] < 0 or state[key] > MAX_SCHEDULE:
			return false
	if state.soft_squash_ordinal > 0 and state.soft_squash_batch == 0:
		return false
	if not state.get("entities") is Array:
		return false
	var registrations := {}
	for entity: Variant in state.entities:
		if not entity is Dictionary or entity.get("code") not in CODES:
			continue
		if not entity.get("squash_batch") is int or not entity.get("squash_ordinal") is int:
			return false
		if entity.squash_batch > state.soft_squash_batch:
			return false
		if entity.squash_batch == 0:
			continue
		if (
			entity.squash_batch == state.soft_squash_batch
			and state.soft_squash_ordinal > 0
			and entity.squash_ordinal > state.soft_squash_ordinal
		):
			return false
		var registration := "%d:%d" % [entity.squash_batch, entity.squash_ordinal]
		if registrations.has(registration):
			return false
		registrations[registration] = true
	return true
