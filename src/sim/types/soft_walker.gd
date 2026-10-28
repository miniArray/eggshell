extends RefCounted
## A small soft walker. It turns at walls and ledges. Landing on it squashes it
## under the player for a moment, then it bursts and knocks nearby enemies away.
## Copies thrown out by the large form tumble until they land.

const Body = preload("res://src/sim/enemy_body.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Elements = preload("res://src/sim/elements.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e23"]
const ENEMY := true
const ELEMENT_REACTIONS := Elements.BURNS | Elements.FREEZES
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const WALK := 0
const SQUASH := 1
const TUMBLE := 2
const SQUASH_TICKS := 15  # Two frames at 8 per second.
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", WALK],
		["timer", 0],
		["contact", 0],
		["pin_dx", 0],
		["slide_from", 0],
		["slide_ticks", 0],
		["slide_total", 0]
	]
)
const WALK_BOX := [-14 * S, -14 * S, 14 * S, 16 * S]
const SQUASH_BOX := [-14 * S, 2 * S, 14 * S, 16 * S]
const MAX_SLIDE := 1024 * 60


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(entity: Dictionary) -> Array:
	return SQUASH_BOX if entity.mode == SQUASH else WALK_BOX


## A copy thrown out with a horizontal speed that eases to zero over `ticks`.
static func tumble_options(facing: int, speed: int, vy: int, ticks: int) -> Dictionary:
	return {
		"facing": facing,
		"vy": vy,
		"mode": TUMBLE,
		"slide_from": speed,
		"slide_ticks": ticks,
		"slide_total": ticks
	}


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Reactions.frozen_step(entity, state, world, bounds(entity), ELEMENT_REACTIONS):
		return
	var box := bounds(entity)
	if Body.spit_step(entity, state, world, box) or Body.hazards(entity, state, world, box):
		return
	if entity.mode == SQUASH:
		entity.vx = 0
		pin(entity, state)
		entity.timer -= 1
		if entity.timer <= 0:
			burst(entity, state, world)
		return
	var grounded := Collision.floor_at(entity, world, box) != 0
	if entity.slide_ticks > 0:
		entity.vx = entity.slide_from * entity.slide_ticks / entity.slide_total
		entity.slide_ticks -= 1
	elif entity.mode == WALK:
		var wet := int(
			World.water_overlaps(
				world, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
			)
		)
		entity.vx = entity.facing * 48 * 60 / (wet + 1)
		if grounded and Motion.edge(entity, world, box):
			entity.facing *= -1
			entity.vx = -entity.vx
	else:
		entity.vx = 0
	var distance: int = entity.vx
	if distance and Motion.move(entity, world, box, distance, true) != distance:
		entity.facing *= -1
		entity.slide_from = -entity.slide_from
	var landed := Motion.gravity_box(entity, world, box)
	if landed and entity.mode == TUMBLE:
		entity.mode = WALK


## Hold the player on the squashed body, keeping the landing offset.
static func pin(entity: Dictionary, state: Dictionary) -> void:
	state.x = entity.x + entity.pin_dx
	state.y = entity.y
	state.vx = 0
	state.vy = 0
	state.on_floor = 1


## The source also knocks enemies within 128 px aside; that reaction is not ported.
static func burst(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	Body.remove(entity, state)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if entity.mode != WALK:
		entity.contact = 0
		return
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching and not entity.contact:
		if entity.y > state.y - 8 * S:
			entity.mode = SQUASH
			entity.timer = SQUASH_TICKS
			entity.vx = 0
			entity.pin_dx = clampi(state.x - entity.x, -64 * S, 64 * S)
			pin(entity, state)
		else:
			Body.hurt(entity, state)
	elif touching and entity.y < state.y - 8 * S:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state) if entity.mode == WALK else 0


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, _from_x: int
) -> void:
	if Reactions.hit(entity, state, world, kind, ELEMENT_REACTIONS, bounds(entity)):
		return
	if entity.mode != SQUASH:
		Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.mode == SQUASH:
		return 0
	hit(entity, state, world, Body.projectile_kind(projectile), projectile.x)
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var result := {"visible": entity.held == 0, "animation": "Walk"}
	if entity.mode == SQUASH:
		result.animation = "Squash"
		result.frame = int(entity.timer <= SQUASH_TICKS / 2)
	return result


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode in [WALK, SQUASH, TUMBLE]
		and entity.timer >= 0
		and entity.timer <= SQUASH_TICKS
		and entity.contact in [0, 1]
		and absi(entity.pin_dx) <= 64 * S
		and absi(entity.slide_from) <= MAX_SLIDE
		and entity.slide_total >= 0
		and entity.slide_total <= 600
		and entity.slide_ticks >= 0
		and entity.slide_ticks <= entity.slide_total
	)
