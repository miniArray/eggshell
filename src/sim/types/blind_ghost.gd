extends RefCounted
## A blindfolded ghost that hunts by ear. A sound makes it stop and listen; a second
## sound while it listens sends it flying toward a point past the sound. When it gets
## there, or after two quiet seconds of listening, it turns around three times in
## confusion and then drifts back and forth on a slow wave. Touching it hurts; eggs
## pass through it, and only clearing the screen removes it.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const World = preload("res://src/sim/world.gd")
const Hits = preload("res://src/sim/hits.gd")
const Sound = preload("res://src/sim/sound_events.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["e39"]
const ENEMY := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const FOCUSING := 0
const CHASING := 1
const CONFUSED := 2
const WANDERING := 3
const FOCUS := 0
const CHASE := 1
const BECOME_CONFUSED := 2
const TURN := 3
const ANIMATIONS := ["Focus", "ChasingLocation", "BecomeConfused", "TurnAround"]
const ANIMATION_FRAMES := [1, 2, 1, 4]
const FRAME_TICKS := 4  # 15 frames per second.
const TURN_FLIP_TICKS := 8  # The turn shows its third frame: the ghost faces the other way.
const HALF := 20 * S
const SPEED := 192 * 60
const PAST_SOUND := 128 * S
const ARRIVED := 48 * S
## Per-tick share of the gap to the chase velocity: 1 - 0.2^(1/60).
const STEER := 26467
const STEER_SCALE := 1000000
const LISTEN_TICKS := 120
const SLOW_TICKS := 30
const TURNS := 3
const TURN_PAUSE_TICKS := 12
const WANDER_PAUSE_TICKS := 24
const RESTART_TURN := 1
const START_WANDER := 2
const FIRST_LEG := 96 * S
const FIRST_LEG_TICKS := 150
const LEG := 192 * S
const LEG_TICKS := 300
const WAVE_TICKS := 150
const WAVE := 32 * S
const MAX_COORD := 0x3fffffffffff
const FIELDS := (
	Body.FIELDS
	+ [
		["mode", FOCUSING],
		["anim", FOCUS],
		["anim_ticks", 0],
		["listen_ticks", 0],
		["pause_ticks", 0],
		["pause_kind", 0],
		["turns_left", TURNS],
		["target_x", 0],
		["target_y", 0],
		["slow_ticks", 0],
		["slow_vx", 0],
		["slow_vy", 0],
		["leg_from", 0],
		["leg_to", 0],
		["leg_tick", 0],
		["leg_ticks", 0],
		["wave_on", 0],
		["wave_phase", 0],
		["heard", 0],
		["contact", 0]
	]
)


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return [-HALF, -HALF, HALF, HALF]


## Sounds made before it woke up are not news to it.
static func activate(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	entity.heard = int(state.get("sound_serial", 0))


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var action := Body.process(entity, state)
	if action in [Body.HELD, Body.GONE]:
		return
	if Sound.heard(state, entity.heard):
		entity.heard = int(state.sound_serial)
		var at_self: bool = state.sound_kind == Sound.RELEASE
		notice(
			entity,
			entity.x if at_self else int(state.sound_x),
			entity.y if at_self else int(state.sound_y)
		)
	var leg_done := _leg_step(entity)
	var slowing: bool = entity.slow_ticks > 0
	if slowing:
		entity.slow_ticks -= 1
	var confuse := false
	if entity.listen_ticks > 0:
		entity.listen_ticks -= 1
		confuse = entity.listen_ticks == 0
	var paused := 0
	if entity.pause_ticks > 0:
		entity.pause_ticks -= 1
		if entity.pause_ticks == 0:
			paused = entity.pause_kind
			entity.pause_kind = 0
	_drift(entity, world)
	if entity.wave_on:
		var before := Motion.sine(entity.wave_phase, WAVE_TICKS, WAVE)
		entity.wave_phase = (entity.wave_phase + 1) % WAVE_TICKS
		entity.y += Motion.sine(entity.wave_phase, WAVE_TICKS, WAVE) - before
	var animation := _animate(entity)
	if entity.mode == FOCUSING:
		if entity.listen_ticks == 0 and not confuse:
			entity.listen_ticks = LISTEN_TICKS
		# The slow-down after arriving ends at rest.
		if slowing:
			entity.vx = entity.slow_vx * entity.slow_ticks / SLOW_TICKS
			entity.vy = entity.slow_vy * entity.slow_ticks / SLOW_TICKS
	if confuse:
		entity.mode = CONFUSED
		_play(entity, BECOME_CONFUSED)
		entity.turns_left = TURNS
	if entity.mode == CONFUSED and entity.anim == TURN:
		if animation.flipped:
			entity.facing = -entity.facing
		if animation.finished:
			entity.turns_left -= 1
			entity.pause_ticks = TURN_PAUSE_TICKS if entity.turns_left > 0 else WANDER_PAUSE_TICKS
			entity.pause_kind = RESTART_TURN if entity.turns_left > 0 else START_WANDER
		if paused == RESTART_TURN:
			entity.anim_ticks = 0
		elif paused == START_WANDER:
			entity.mode = WANDERING
			entity.wave_on = 1
			_start_leg(entity, FIRST_LEG, FIRST_LEG_TICKS)
	if entity.mode == CHASING:
		_chase(entity)
	if entity.mode == WANDERING:
		if leg_done:
			entity.anim_ticks = 0
		elif entity.anim == TURN:
			if animation.flipped:
				entity.facing = -entity.facing
			if animation.finished:
				_start_leg(entity, LEG, LEG_TICKS)


## A sound at (sx, sy): listen, or chase if it was already listening.
static func notice(entity: Dictionary, sx: int, sy: int) -> void:
	entity.listen_ticks = 0
	entity.wave_on = 0
	entity.wave_phase = 0
	entity.leg_ticks = 0
	entity.leg_tick = 0
	# Aim past the sound, away from the ghost; a sound at the ghost itself aims right.
	var heading := _heading(sx - entity.x, sy - entity.y)
	entity.target_x = sx + Motion.turn_cosine(heading, PAST_SOUND)
	entity.target_y = sy + Motion.turn_sine(heading, PAST_SOUND)
	if entity.anim != FOCUS and entity.anim != CHASE:
		entity.mode = FOCUSING
		_play(entity, FOCUS)
		entity.facing = -1 if sx < entity.x else 1
	elif entity.anim == FOCUS:
		entity.mode = CHASING
		_play(entity, CHASE)
		entity.slow_ticks = 0


static func _heading(dx: int, dy: int) -> int:
	return 0 if dx == 0 and dy == 0 else Motion.angle_to(dx, dy)


static func _chase(entity: Dictionary) -> void:
	var heading := _heading(entity.target_x - entity.x, entity.target_y - entity.y)
	var aim_x := Motion.turn_cosine(heading, SPEED)
	var aim_y := Motion.turn_sine(heading, SPEED)
	entity.vx += (aim_x - entity.vx) * STEER / STEER_SCALE
	entity.vy += (aim_y - entity.vy) * STEER / STEER_SCALE
	entity.facing = -1 if entity.vx < 0 else 1
	var dx: int = entity.target_x - entity.x
	var dy: int = entity.target_y - entity.y
	if dx * dx + dy * dy < ARRIVED * ARRIVED:
		_play(entity, FOCUS)
		entity.mode = FOCUSING
		entity.slow_ticks = SLOW_TICKS
		entity.slow_vx = entity.vx
		entity.slow_vy = entity.vy


static func _play(entity: Dictionary, animation: int) -> void:
	entity.anim = animation
	entity.anim_ticks = 0


## Advance the animation clock: whether the turn reached its flipped frame or finished.
static func _animate(entity: Dictionary) -> Dictionary:
	var result := {"flipped": false, "finished": false}
	if entity.anim == FOCUS:
		return result
	var length: int = ANIMATION_FRAMES[entity.anim] * FRAME_TICKS
	if entity.anim_ticks >= length:
		return result
	entity.anim_ticks += 1
	result.flipped = entity.anim == TURN and entity.anim_ticks == TURN_FLIP_TICKS
	result.finished = entity.anim_ticks == length
	if result.finished and entity.anim == BECOME_CONFUSED:
		_play(entity, TURN)
		result.finished = false
	return result


## An eased sideways leg in the facing direction.
static func _start_leg(entity: Dictionary, distance: int, ticks: int) -> void:
	entity.leg_from = entity.x
	entity.leg_to = entity.x + entity.facing * distance
	entity.leg_tick = 0
	entity.leg_ticks = ticks


## One tick of the eased sideways leg; true on the tick it ends.
static func _leg_step(entity: Dictionary) -> bool:
	if entity.leg_ticks <= 0:
		return false
	entity.leg_tick += 1
	var length: int = entity.leg_ticks
	var tick: int = entity.leg_tick
	var delta: int = entity.leg_to - entity.leg_from
	var part: int
	if 2 * tick < length:
		part = delta * 2 * tick * tick / (length * length)
	else:
		var rest := length - tick
		part = delta - delta * 2 * rest * rest / (length * length)
	entity.x = entity.leg_from + part
	if tick < length:
		return false
	entity.leg_ticks = 0
	entity.leg_tick = 0
	return true


## Fly by the saved velocity. Terrain stops each axis: the ghost backs out up to the
## distance it moved, in whole pixels, or returns to where it was, and that axis stops.
static func _drift(entity: Dictionary, world: Dictionary) -> void:
	for horizontal: bool in [true, false]:
		var key := "x" if horizontal else "y"
		var speed_key := "vx" if horizontal else "vy"
		var distance: int = entity[speed_key]
		if distance == 0:
			continue
		var start: int = entity[key]
		entity[key] = start + distance
		if not _blocked(entity, world):
			continue
		var back := -signi(distance) * S
		var limit := maxi(absi(_floor_pixels(distance)), 1)
		var free := false
		for _step in limit:
			entity[key] += back
			if not _blocked(entity, world):
				free = true
				break
		if not free:
			entity[key] = start
		entity[speed_key] = 0


static func _floor_pixels(value: int) -> int:
	return value / S if value >= 0 else -((-value + S - 1) / S)


## Only terrain tiles stop it; solid objects, the map's side borders included, do not.
static func _blocked(entity: Dictionary, world: Dictionary) -> bool:
	if not world.has("layers"):
		return false
	var box := bounds(entity)
	return World.tiles_overlap_box(
		world, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
	)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	var touching := Body.player_overlap(entity, state, bounds(entity))
	if touching:
		Body.hurt(entity, state)
	entity.contact = int(touching)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind == Hits.CLEAR:
		Body.remove(entity, state)


## Thrown things pass through it.
static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var last: int = ANIMATION_FRAMES[entity.anim] - 1
	return {
		"visible": entity.held == 0,
		"animation": ANIMATIONS[entity.anim],
		"frame": mini(entity.anim_ticks / FRAME_TICKS, last)
	}


static func valid(entity: Dictionary) -> bool:
	var speeds: Array = [entity.vx, entity.vy, entity.slow_vx, entity.slow_vy]
	var coordinates: Array = [entity.target_x, entity.target_y, entity.leg_from, entity.leg_to]
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.mode >= FOCUSING
		and entity.mode <= WANDERING
		and entity.anim >= FOCUS
		and entity.anim <= TURN
		and entity.anim_ticks >= 0
		and entity.anim_ticks <= ANIMATION_FRAMES[entity.anim] * FRAME_TICKS
		and entity.listen_ticks >= 0
		and entity.listen_ticks <= LISTEN_TICKS
		and entity.pause_ticks >= 0
		and entity.pause_ticks <= WANDER_PAUSE_TICKS
		and entity.pause_kind in [0, RESTART_TURN, START_WANDER]
		and entity.turns_left >= 0
		and entity.turns_left <= TURNS
		and entity.slow_ticks >= 0
		and entity.slow_ticks <= SLOW_TICKS
		and entity.leg_ticks in [0, FIRST_LEG_TICKS, LEG_TICKS]
		and entity.leg_tick >= 0
		and entity.leg_tick <= entity.leg_ticks
		and entity.wave_on in [0, 1]
		and entity.wave_phase >= 0
		and entity.wave_phase < WAVE_TICKS
		and entity.heard >= 0
		and entity.contact in [0, 1]
		and speeds.all(func(value: int) -> bool: return absi(value) <= SPEED)
		and coordinates.all(func(value: int) -> bool: return absi(value) <= MAX_COORD)
	)
