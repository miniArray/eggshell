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
## Knocked aside by a nearby burst: the speed eases to zero, with a hop on each landing.
const KNOCKED := 3
const KNOCK_SPEED := 448 * 60
const KNOCK_TICKS := 60  # 1 s
const KNOCK_RANGE := 128
const KNOCK_PAUSE := 2  # Standing ticks before it walks again.
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
const SQUASH_LOW_BOX := [-14 * S, 6 * S, 14 * S, 14 * S]
const MAX_SLIDE := 1024 * 60


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(entity: Dictionary) -> Array:
	if entity.mode != SQUASH:
		return WALK_BOX
	# The squash's second picture (from 1/8 s) stands 2 px shorter at the bottom.
	return SQUASH_BOX if entity.timer > SQUASH_TICKS - 9 else SQUASH_LOW_BOX


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
		entity.timer -= 1
		if entity.timer <= 0:
			burst(entity, state, world)
			return
		# The body keeps its gravity, so the shorter picture settles 2 px lower.
		Motion.gravity_box(entity, world, bounds(entity))
		pin(entity, state)
		return
	# A body knocked in this step's earlier burst still takes its own step now.
	var pending: bool = entity.mode == KNOCKED and entity.timer > 0 and entity.slide_ticks > 0
	if entity.mode == KNOCKED and not pending:
		_knocked_step(entity, state, world, box)
		return
	if pending:
		entity.timer = 0
	var grounded := Collision.floor_at(entity, world, box) != 0
	if entity.slide_ticks > 0 and not pending:
		entity.vx = entity.slide_from * entity.slide_ticks / entity.slide_total
		entity.slide_ticks -= 1
	elif entity.mode == WALK or pending:
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
	if pending:
		_hop(entity, landed)


## Knock-back (Global Events 98-107, `knockBackEnemy`): the Platform speed follows a
## linear 1 s tween from the knock speed to 0. Each landing while it is faster than 24
## px/s hops at -(speed / 2 + 160). Against a wall faster than 64 px/s the tween restarts
## at 48 px/s away from the wall over 1.5 s. When the tween ends the body stands, then
## turns toward the player and walks.
static func _knocked_step(
	entity: Dictionary, state: Dictionary, world: Dictionary, box: Array
) -> void:
	if entity.slide_ticks == 0:
		entity.vx = 0
		Motion.gravity_box(entity, world, box)
		entity.timer -= 1
		if entity.timer <= 0:
			entity.timer = 0
			entity.mode = WALK
			if entity.x != state.x:
				entity.facing = -1 if entity.x > state.x else 1
		return
	var speed: int = entity.slide_from * entity.slide_ticks / entity.slide_total
	entity.slide_ticks -= 1
	entity.vx = speed
	if speed and Motion.move(entity, world, box, speed, true) != speed and absi(speed) > 64 * 60:
		entity.facing = -signi(speed)
		entity.slide_from = entity.facing * 48 * 60
		entity.slide_total = 90
		entity.slide_ticks = 89
	_hop(entity, Motion.gravity_box(entity, world, box))
	if entity.slide_ticks == 0:
		entity.timer = KNOCK_PAUSE


static func _hop(entity: Dictionary, landed: bool) -> void:
	var speed: int = absi(entity.slide_from * entity.slide_ticks / entity.slide_total)
	if landed and speed > 24 * 60:
		entity.vy = -(speed / 2 + 160 * 60)


## Hold the player on the squashed body, keeping the landing offset. Only the position
## is held: the player's own motion (speed, gravity, flutter) runs on underneath.
static func pin(entity: Dictionary, state: Dictionary) -> void:
	state.x = entity.x + entity.pin_dx
	state.y = entity.y


## Enemies 1281-1285: the burst knocks soft walkers within 128 px aside (vx -448 left
## of it, +448 right of it), then removes the body. Other enemy kinds are not knocked
## yet (not ported).
static func burst(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var later := false
	for other: Dictionary in state.entities:
		if is_same(other, entity):
			later = true
			continue
		if not _knockable(other) or other.x == entity.x:
			continue
		if absi(other.y - entity.y) >= KNOCK_RANGE * S:
			continue
		if absi(other.x - entity.x) >= KNOCK_RANGE * S:
			continue
		other.mode = KNOCKED
		other.slide_from = KNOCK_SPEED * (1 if other.x > entity.x else -1)
		other.slide_total = KNOCK_TICKS
		other.slide_ticks = KNOCK_TICKS
		other.timer = int(later)
		if not later:
			_hop(other, Collision.floor_at(other, world, bounds(other)) != 0)
	Body.remove(entity, state)


static func _knockable(other: Dictionary) -> bool:
	return (
		other.get("code", "") in CODES
		and other.status == 1
		and other.mode in [WALK, TUMBLE, KNOCKED]
		and not other.held
		and not other.spat
		and not other.hidden
		and not other.get("frozen", 0)
	)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	if Reactions.frozen_contact(entity, state, input, bounds(entity)):
		return
	if entity.mode == SQUASH:
		# The hold puts the player back after its own move in this step.
		pin(entity, state)
		return
	if entity.mode not in [WALK, KNOCKED]:
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
		and entity.mode in [WALK, SQUASH, TUMBLE, KNOCKED]
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
