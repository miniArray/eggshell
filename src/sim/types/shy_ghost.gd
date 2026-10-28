extends RefCounted
## A shy ghost that drifts toward the player through terrain, but hides while the
## player faces it. Touching it hurts. Only a hit at its face while it moves
## defeats it, leaving a star. The pink forms turn into a solid block while hiding.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e26"]
const ENEMY := true
const GOAL_COIN := true
const SOLID := 1
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const STALK := 0
const HIDE := 1
const TURN_TICKS := 12  # 0.2 s before hiding or coming out.
const PEEK_TICKS := 15  # 0.25 s peek.
const FIELDS := (
	Body.FIELDS + [["phase", STALK], ["timer", 0], ["peek", 0], ["peek_wait", 0], ["contact", 0]]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 3)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func size(entity: Dictionary) -> int:
	return (64 if entity.variant in [1, 3] else 32) * S


static func pink(entity: Dictionary) -> bool:
	return entity.variant in [2, 3]


static func bounds(entity: Dictionary) -> Array:
	var half: int = size(entity) * 7 / 16
	return [-half, -half, half, half]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1 or not pink(entity) or entity.phase != HIDE:
		return []
	var half: int = size(entity) / 2
	return [entity.x - half, entity.y - half, entity.x + half, entity.y + half]


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	var width: int = size(entity)
	var right_of: bool = entity.x > state.x + width / 2
	var left_of: bool = entity.x < state.x - width / 2
	var watched: bool = (right_of and state.facing > 0) or (left_of and state.facing < 0)
	var reach: int = width * 3 / 2 if entity.variant == 2 else width
	var far: bool = absi(entity.x - state.x) > reach
	if entity.timer:
		entity.timer -= 1
		if entity.timer == 0:
			entity.phase = HIDE if entity.phase == STALK else STALK
			entity.peek = 0
			entity.peek_wait = 0
		return
	if entity.phase == STALK:
		if watched:
			entity.timer = TURN_TICKS
			return
		var heading := Motion.angle_to(state.x - entity.x, state.y - entity.y)
		entity.x += 64 * 60 * Motion.turn_cosine(heading) / S
		entity.y += 64 * 60 * Motion.turn_sine(heading) / S
		entity.facing = 1 if state.x > entity.x else -1
	else:
		if not watched and (right_of or left_of) and far:
			entity.timer = TURN_TICKS
			return
		if not pink(entity):
			peek_step(entity, state)


static func peek_step(entity: Dictionary, state: Dictionary) -> void:
	if entity.peek:
		entity.peek -= 1
	elif entity.peek_wait == 0:
		entity.peek_wait = Motion.random_ticks(state, 480, 960)
	else:
		entity.peek_wait -= 1
		if entity.peek_wait == 0:
			entity.peek = PEEK_TICKS


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


## Defeated only by a hit at its face while it moves, leaving a star.
static func struck(entity: Dictionary, state: Dictionary, world: Dictionary, travel: int) -> bool:
	if entity.phase != STALK or entity.timer or travel == 0:
		return false
	if signi(travel) != -entity.facing:
		return false
	var registry: Script = load("res://src/sim/registry.gd")
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
	return true


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, _kind: int, from_x: int
) -> void:
	struck(entity, state, world, signi(entity.x - from_x))


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var travel: int = projectile.get("vx", 0)
	return 3 if struck(entity, state, world, travel) else 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var name := "%d%s" % [entity.variant, "Hide" if entity.phase == HIDE else "Stalk"]
	return {"visible": entity.held == 0, "animation": name, "frame": int(entity.peek > 0)}


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant <= 3
		and entity.phase in [STALK, HIDE]
		and entity.timer >= 0
		and entity.timer <= TURN_TICKS
		and entity.peek >= 0
		and entity.peek <= PEEK_TICKS
		and entity.peek_wait >= 0
		and entity.peek_wait <= 960
		and entity.contact in [0, 1]
	)
