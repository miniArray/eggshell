extends RefCounted
## Run phases and companion movement. All mutable values belong to the schema.

const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Sound = preload("res://src/sim/sound_events.gd")
const Moves = preload("res://src/sim/moves.gd")
const Screen = preload("res://src/sim/screen.gd")
const PLAY := 0
const REJOIN := 1
const DEAD := 2
const FADE_OUT := 3
const RESPAWN := 4
const FADE_IN := 5
const CHECKPOINT := 6
const GOAL := 7
const COMPLETE := 8
const ATTACHED := 0
const LAUNCH := 1
const BUBBLE := 2
const RETURNING := 3
const TAKEN := 4
const NONE := 0
const PIT := 1
const COUNTDOWN := 2
const HAZARD := 3
const CRUSH := 4
const QUICK := 5
# Hurt phases. KNOCKED is the knock-back pose of a first dry-land hit; landing in it starts
# LOOK_AROUND. `hurt` counts the steps that ignore movement input in either phase.
const HURT_NONE := 0
const HURT_KNOCKED := 1
const HURT_LOOK_AROUND := 2
# Lock lengths in steps, counted from the step that sets them. The reference game ends each
# pose with an event that runs after it has read input for that frame, and its hit events run
# after input in the frame the hit lands, so each lock is longer than its nominal time:
# 0.6 s knock-back = 38, 1 s spin = 63, 42-frame look-around after landing = 43.
const KNOCKED_LOCK := 38
const SPIN_LOCK := 63
const LOOK_AROUND_LOCK := 43
const MAX_HURT := 63
# Contact immunity after a hit: the reference game counts its 2 s flash down by the frame
# time and ends it when the remainder is no longer positive; 120 frame-time subtractions
# leave a rounding remainder, so a new hit is possible on the 121st step.
const IMMUNITY := 121
# The countdown loses one unit every 46 steps while separated: its 0.75 s timer fires
# after 45 frames and is restarted on the following frame.
const COUNTDOWN_STEPS := 46
# A catch freezes the world while the companion rises 96 px over 24 steps and drops to
# the saddle over 24 more; each of the two moves ends one step late, and play resumes
# on the step after the second ends: 51 steps.
const REJOIN_STEPS := 51
# The launch arc takes 36 steps; the bubble forms on the 38th (its tween reports the end
# one step late and the bubble's body moves from the next frame).
const LAUNCH_STEPS := 38
# Death and restart timing in steps. An ordinary death waits 240 steps, then fades for 61:
# the reference game restarts on the step after its 60-step fade completes. A quick death
# fades for 32. After the respawn the first step holds the body, the second moves it
# without input, and input works from the third.
const DEATH_WAIT := 240
const DEATH_FADE := 61
const QUICK_FADE := 32
const RESTART_STEPS := 3
const COIN := 0
const RED_COIN := 1
const FLOWER := 2
const STAR := 3
const MAX_COUNT := 9223372036854775807
const MAX_POSITION := MAX_COUNT / 16384
const PLAYER_BOX := [-12 * S, -56 * S, 12 * S, 0]
const BUBBLE_BOX := [-30 * S, -60 * S, 30 * S, 0]
const BUBBLE_POINTS := [-22, -52, 0, -60, 22, -52, 30, -30, 22, -8, 0, 0, -22, -8, -30, -30]
const RESCUE_OFFSETS := [[-32, -22], [-16, -14], [32, -22], [16, -14]]
const RESCUER_POINTS := [-4, -12, 0, -24, 3, -12, 13, 0, 11, 19, 0, 23, -10, 17, -12, 0]
const PLAYER_FIELDS := [
	["hurt", 0],
	["hurt_phase", HURT_NONE],
	["invulnerable", 0],
	["health", 10],
	["health_wait", 0],
	["separated", 0],
	["recovery_x", 0],
	["recovery_y", 0],
	["recovery_delay", 0],
	["hits", 0],
	["hurt_deceleration", 0],
	["life_phase", PLAY],
	["life_ticks", 0],
	["death_cause", NONE],
	["quick_death", 0],
	["attempt_ticks", 0],
	["companion_mode", ATTACHED],
	["companion_age", 0],
	["companion_vx", 0],
	["companion_vy", 0],
	["companion_direction", 1],
	["companion_from_x", 0],
	["companion_from_y", 0],
	["companion_dx", 0],
	["bubble_bound_ticks", 0],
	["bubble_bound_from_x", 0],
	["bubble_bound_to_x", 0],
	["separation_grace", 0],
	["rescue_active", 0],
	["rescue_mask", 0],
	["rescue_ticks", 0],
	["rescue_1_x", 0],
	["rescue_1_y", 0],
	["rescue_2_x", 0],
	["rescue_2_y", 0],
	["rescue_3_x", 0],
	["rescue_3_y", 0],
	["rescue_4_x", 0],
	["rescue_4_y", 0],
	["checkpoint_awards", 0],
	["goal_from_x", 0],
	["goal_from_y", 0],
	["goal_x", 0],
	["goal_y", 0]
]
const LEVEL_FIELDS := [
	["life_ready", 0],
	["run_spawn_x", 0],
	["run_spawn_y", 0],
	["run_spawn_map", 1],
	["run_spawn_facing", 1],
	["checkpoint_id", 0],
	["checkpoint_map", 1],
	["checkpoint_x", 0],
	["checkpoint_y", 0],
	["checkpoint_health", 10],
	["checkpoint_redcoins", 0],
	["checkpoint_flowers", 0],
	["coins", 0],
	["redcoins", 0],
	["flowers", 0],
	["play_ticks", 0],
	["total_play_ticks", 0],
	["checkpoint_play_ticks", 0]
]

static var _bubble_body_cache: Array = []


static func ensure_fields(state: Dictionary) -> void:
	for list: Array in [PLAYER_FIELDS, LEVEL_FIELDS]:
		for field: Array in list:
			if not state.has(field[0]):
				state[field[0]] = field[1]


static func initialize(state: Dictionary, world: Dictionary) -> void:
	ensure_fields(state)
	if state.life_ready:
		return
	state.life_ready = 1
	state.run_spawn_x = int(world.spawn_x)
	state.run_spawn_y = int(world.spawn_y)
	state.run_spawn_map = int(state.get("map_index", 1))
	state.run_spawn_facing = int(state.facing)
	if state.companion_mode == ATTACHED:
		_attach_position(state)


static func before_step(
	state: Dictionary,
	world: Dictionary,
	reset_map: Callable = Callable(),
	change_map: Callable = Callable()
) -> bool:
	initialize(state, world)
	if state.life_phase != PLAY:
		return _phase_step(state, world, reset_map, change_map)
	state.play_ticks = _plus_one(state.play_ticks)
	state.attempt_ticks = _plus_one(state.attempt_ticks)
	state.total_play_ticks = _plus_one(state.total_play_ticks)
	state.invulnerable = maxi(0, state.invulnerable - 1)
	_hurt_step(state)
	state.separation_grace = maxi(0, state.separation_grace - 1)
	# The companion moves before the countdown: captors summoned at zero appear after the
	# bubble's last move and first chase it on the next step.
	_companion_step(state, world)
	_countdown_step(state, world)
	return false


static func blocks_step(state: Dictionary) -> bool:
	# The last restart step runs the world and moves the body, without input.
	var phase := int(state.get("life_phase", PLAY))
	return phase != PLAY and not (phase == FADE_IN and int(state.get("life_ticks", 0)) == 1)


static func body_moves(state: Dictionary) -> bool:
	# After a fall, a countdown or a quick restart the body keeps its motion without
	# control until the restart. A hazard holds it.
	return (
		int(state.get("life_phase", PLAY)) in [DEAD, FADE_OUT]
		and int(state.get("death_cause", NONE)) in [PIT, COUNTDOWN, QUICK]
	)


static func first_dead_step(state: Dictionary) -> bool:
	# Input read in the frame of the death still steers the body for one step.
	var ticks := int(state.get("life_ticks", 0))
	if int(state.get("life_phase", PLAY)) == DEAD:
		return ticks == DEATH_WAIT - 1
	var quick: bool = (
		int(state.get("death_cause", NONE)) == QUICK or int(state.get("quick_death", 0)) != 0
	)
	return quick and ticks == QUICK_FADE - 1


static func locks_input(state: Dictionary) -> bool:
	# Movement input is ignored in a hurt pose and on the last restart step.
	return int(state.get("hurt", 0)) != 0 or int(state.get("life_phase", PLAY)) == FADE_IN


static func after_step(state: Dictionary, world: Dictionary) -> void:
	if state.life_phase != PLAY:
		return
	# The pose height comes from fixed source metadata, never from a graphics pack.
	if state.y > world.height + Moves.pit_height(state):
		kill(state, PIT)
		return
	var left: int = state.x + PLAYER_BOX[0]
	var top: int = state.y + PLAYER_BOX[1]
	var right: int = state.x + PLAYER_BOX[2]
	var bottom: int = state.y + PLAYER_BOX[3]
	if (
		World.lava_overlaps(world, left, top, right, bottom)
		or World.named_overlaps(world, World.SPIKE_LAYER, left, top, right, bottom)
	):
		kill(state, HAZARD)
		return
	_look_around_on_landing(state)
	if state.companion_mode == BUBBLE and not state.get("captured_by", 0):
		catch_companion(
			state,
			state.x + PLAYER_BOX[0],
			state.y + PLAYER_BOX[1],
			state.x + PLAYER_BOX[2],
			state.y + PLAYER_BOX[3]
		)
	elif state.companion_mode == ATTACHED:
		_attach_position(state)


static func separate(
	state: Dictionary, velocity: int, instant: bool = false, world: Dictionary = {}
) -> void:
	ensure_fields(state)
	if state.separated or state.life_phase != PLAY:
		return
	_attach_position(state)
	state.separated = 1
	state.hits = _plus_one(state.hits)
	state.health_wait = COUNTDOWN_STEPS
	state.companion_mode = BUBBLE if instant else LAUNCH
	state.companion_age = 0
	state.recovery_delay = 0 if instant else 36
	state.companion_from_x = state.recovery_x
	state.companion_from_y = state.recovery_y
	var displacement := -velocity * 15
	state.companion_dx = (
		maxi(displacement, 112 * S) if displacement >= 0 else mini(displacement, -112 * S)
	)
	state.companion_direction = 1 if state.companion_dx >= 0 else -1
	state.companion_vx = 0
	state.companion_vy = 0
	if instant:
		state.companion_direction = 1 if state.recovery_x >= state.x else -1
	# Without the world the next companion step summons the captors.
	if state.health == 0 and instant and not world.is_empty():
		_start_rescue(state, world)


static func catch_companion(
	state: Dictionary, left: int, top: int, right: int, bottom: int
) -> bool:
	if state.life_phase != PLAY or state.companion_mode != BUBBLE or state.get("captured_by", 0):
		return false
	if left > right or top > bottom or state.bubble_bound_ticks:
		return false
	var box := [
		state.recovery_x - 30 * S,
		state.recovery_y - 60 * S,
		state.recovery_x + 30 * S,
		state.recovery_y
	]
	if right < box[0] or left > box[2] or bottom < box[1] or top > box[3]:
		return false
	var points := _bubble_points()
	if not Polygon.overlaps_box(
		points,
		maxi(left, box[0]) - state.recovery_x,
		maxi(top, box[1]) - state.recovery_y,
		mini(right, box[2]) - state.recovery_x,
		mini(bottom, box[3]) - state.recovery_y
	):
		return false
	state.life_phase = REJOIN
	state.life_ticks = REJOIN_STEPS
	state.companion_mode = RETURNING
	state.companion_from_x = state.recovery_x
	state.companion_from_y = state.recovery_y
	state.companion_age = 0
	state.companion_vx = 0
	state.companion_vy = 0
	state.rescue_active = 0
	state.rescue_mask = 0
	state.rescue_ticks = 0
	state.health_wait = 120 if state.health < 10 else 0
	return true


static func kill(state: Dictionary, cause: int = HAZARD, fast: bool = false) -> bool:
	ensure_fields(state)
	if state.life_phase != PLAY or cause < PIT or cause > QUICK:
		return false
	state.deaths = _plus_one(int(state.get("deaths", 0)))
	state.death_cause = cause
	state.life_phase = FADE_OUT if fast or state.quick_death else DEAD
	state.life_ticks = QUICK_FADE if fast or state.quick_death else DEATH_WAIT
	if cause == HAZARD:
		# A hazard holds the body where it died.
		state.vx = 0
		state.vy = 0
	state.hurt = 0
	state.hurt_phase = HURT_NONE
	state.invulnerable = 0
	state.captured_by = 0
	if state.life_phase == DEAD:
		# Only the slow death voices the player; a quick restart is silent to listeners.
		Sound.player(state)
	return true


static func quick_restart(state: Dictionary) -> bool:
	return kill(state, QUICK, true)


static func touch_goal(state: Dictionary, entity: Dictionary) -> bool:
	ensure_fields(state)
	if state.life_phase != PLAY or state.separated or state.get("captured_by", 0):
		return false
	if not entity.get("x") is int or not entity.get("y") is int:
		return false
	state.life_phase = GOAL
	state.life_ticks = 180
	state.goal_from_x = state.x
	state.goal_from_y = state.y
	state.goal_x = int(entity.x)
	state.goal_y = int(entity.y) + 32 * S
	state.vx = 0
	state.vy = 0
	state.movement = 5
	Sound.player(state)
	return true


static func goal_coin(state: Dictionary) -> void:
	if int(state.get("life_phase", PLAY)) == GOAL:
		state.coins = _plus_one(int(state.get("coins", 0)))


static func touch_checkpoint(state: Dictionary, entity: Dictionary) -> bool:
	ensure_fields(state)
	if state.life_phase != PLAY or state.get("captured_by", 0) or entity.get("collected", 0):
		return false
	if (
		absi(state.x - int(entity.x)) >= 16 * S
		or state.y <= entity.y - 48 * S
		or state.y - 56 * S >= entity.y + 48 * S
	):
		return false
	if (
		not entity.get("source_index") is int
		or entity.source_index < 0
		or entity.source_index == MAX_COUNT
		or not entity.get("respawn_x") is int
		or not entity.get("respawn_y") is int
	):
		return false
	var map_index := int(entity.get("map_index", state.get("map_index", 1)))
	if map_index < 1 or map_index > int(state.get("map_count", map_index)):
		return false
	entity.collected = 1
	state.checkpoint_id = entity.source_index + 1
	state.checkpoint_map = map_index
	state.checkpoint_x = int(entity.respawn_x)
	state.checkpoint_y = int(entity.respawn_y)
	state.checkpoint_redcoins = state.redcoins
	state.checkpoint_flowers = state.flowers
	state.checkpoint_play_ticks = state.play_ticks
	for item: Dictionary in state.get("entities", []):
		item.checkpoint_collected = int(item.get("collected", 0))
	state.checkpoint_awards = clampi(int(entity.get("health_bonus", 10)), 0, 30)
	if state.separated:
		state.health_wait = 60
	state.life_phase = CHECKPOINT
	if state.checkpoint_awards and state.health < 30:
		state.life_ticks = 6
	else:
		state.checkpoint_awards = 0
		state.checkpoint_health = maxi(10, state.health)
		state.life_ticks = 45
	return true


static func collect(state: Dictionary, kind: int, entity: Dictionary = {}) -> bool:
	ensure_fields(state)
	if state.life_phase != PLAY or kind not in [COIN, RED_COIN, FLOWER, STAR]:
		return false
	if not entity.is_empty():
		if entity.get("collected", 0):
			return false
		entity.collected = 1
	match kind:
		COIN:
			state.coins = _plus_one(state.coins)
		RED_COIN:
			state.redcoins = _plus_one(state.redcoins)
		FLOWER:
			state.flowers = _plus_one(state.flowers)
		STAR:
			state.health = mini(30, state.health + 1)
	return true


static func score(state: Dictionary) -> int:
	var remaining := MAX_COUNT - int(state.health)
	if int(state.redcoins) > remaining:
		return MAX_COUNT
	remaining -= int(state.redcoins)
	if int(state.flowers) > remaining / 10:
		return MAX_COUNT
	return int(state.health) + int(state.redcoins) + 10 * int(state.flowers)


static func start_hurt(state: Dictionary, lock: int, knocked: bool) -> void:
	## Start a movement-input lock. A knocked pose turns into the look-around on landing.
	ensure_fields(state)
	state.hurt = clampi(lock, 0, MAX_HURT)
	state.hurt_phase = HURT_KNOCKED if knocked and state.hurt else HURT_NONE


static func _hurt_step(state: Dictionary) -> void:
	state.hurt = maxi(0, state.hurt - 1)
	# The knock-back pose ends one step before its input lock does.
	if state.hurt == 0 or (state.hurt == 1 and state.hurt_phase == HURT_KNOCKED):
		state.hurt_phase = HURT_NONE


static func _look_around_on_landing(state: Dictionary) -> void:
	if state.hurt_phase == HURT_KNOCKED and state.get("on_floor", 0):
		state.hurt_phase = HURT_LOOK_AROUND
		state.hurt = LOOK_AROUND_LOCK


static func _countdown_step(state: Dictionary, world: Dictionary) -> void:
	if state.separated:
		if state.health > 0:
			if state.health_wait <= 0:
				state.health_wait = COUNTDOWN_STEPS
			state.health_wait -= 1
			if state.health_wait <= 0:
				state.health -= 1
				state.health_wait = COUNTDOWN_STEPS if state.health else 0
				if state.health == 0 and state.companion_mode == BUBBLE:
					_start_rescue(state, world)
	elif state.health < 10:
		if state.health_wait <= 0:
			state.health_wait = 120
		state.health_wait -= 1
		if state.health_wait == 0:
			state.health += 1
			state.health_wait = 120 if state.health < 10 else 0


static func _companion_step(state: Dictionary, world: Dictionary) -> void:
	match state.companion_mode:
		LAUNCH:
			state.companion_age += 1
			var age: int = mini(36, state.companion_age)
			var leg := mini(age, 36 - age)
			state.recovery_x = state.companion_from_x + state.companion_dx * age / 36
			state.recovery_y = state.companion_from_y - 56 * S * leg * (36 - leg) / 324
			state.recovery_delay = 36 - age
			# The arc ends after 36 steps; the bubble forms two steps later and its body
			# first moves in that step, out of any terrain it formed in.
			if state.companion_age >= LAUNCH_STEPS:
				state.companion_mode = BUBBLE
				state.companion_age = 0
				_bubble_settle(state, world)
				if state.health == 0:
					_start_rescue(state, world)
		BUBBLE:
			if state.health == 0 and not state.rescue_active:
				_start_rescue(state, world)
			if state.rescue_active:
				# Contact still wins while the capture agents have not taken the companion.
				if catch_companion(
					state, state.x - 12 * S, state.y - 56 * S, state.x + 12 * S, state.y
				):
					return
				_rescue_step(state)
				return
			_bubble_step(state, world)
		TAKEN:
			state.recovery_y -= 256 * 60
			for index in 4:
				state["rescue_%d_y" % (index + 1)] -= 256 * 60
			state.rescue_ticks -= 1
			if state.rescue_ticks <= 0:
				kill(state, COUNTDOWN)


static func _bubble_step(state: Dictionary, world: Dictionary) -> void:
	state.companion_age = 61 if state.companion_age >= 300 else state.companion_age + 1
	var age: int = state.companion_age
	if age <= 60:
		state.companion_vy = -192 * 60 * age / 60
	else:
		# The swing starts one step after the ramp ends (the ramp reports its end late).
		var leg := (age - 61) % 240
		state.companion_vy = -192 * 60 + 384 * 60 * mini(leg, 240 - leg) / 120
	var previous_vx: int = state.companion_vx
	state.companion_vx = clampi(
		state.companion_vx + state.companion_direction * 512, -48 * 60, 48 * 60
	)
	if state.bubble_bound_ticks:
		state.bubble_bound_ticks -= 1
		state.recovery_x = (
			state.bubble_bound_from_x
			+ (
				(state.bubble_bound_to_x - state.bubble_bound_from_x)
				* (6 - state.bubble_bound_ticks)
				/ 6
			)
		)
		state.recovery_y += state.companion_vy
		return
	var bubble_body := _bubble_body()
	if Collision.overlaps({"x": state.recovery_x, "y": state.recovery_y}, world, bubble_body):
		# An embedded bubble drifts toward the player on both axes.
		state.recovery_x += signi(state.x - state.recovery_x) * 96 * 60
		state.recovery_y += signi(state.y - state.recovery_y) * 96 * 60
	var body := {
		"x": state.recovery_x,
		"y": state.recovery_y,
		"vx": state.companion_vx,
		"vy": state.companion_vy
	}
	if Collision.prepare(body, world, bubble_body):
		# The body moves by the mean of the old and new speed, and not at all from rest.
		var distance: int = (previous_vx + body.vx) / 2 if previous_vx else 0
		var actual := Collision.horizontal(body, world, bubble_body, distance, 0, false, 640 * 60)
		if actual != distance or body.vx == 0:
			state.companion_direction *= -1
		Collision.vertical(body, world, bubble_body, body.vy)
	state.recovery_x = body.x
	state.recovery_y = body.y
	state.companion_vx = body.vx
	state.companion_vy = body.vy
	var left := 32 * S
	var right: int = maxi(left, world.width - 32 * S)
	if state.recovery_x < left or state.recovery_x > right:
		state.bubble_bound_ticks = 6
		state.bubble_bound_from_x = state.recovery_x
		state.bubble_bound_to_x = clampi(state.recovery_x, left, right)
		state.companion_direction = 1 if state.recovery_x < left else -1
		state.companion_vx = 0


static func _bubble_settle(state: Dictionary, world: Dictionary) -> void:
	# The new bubble's first body step: no speed yet, only the push out of terrain.
	var body := {"x": state.recovery_x, "y": state.recovery_y, "vx": 0, "vy": 0}
	Collision.prepare(body, world, _bubble_body())
	state.recovery_x = body.x
	state.recovery_y = body.y


static func _start_rescue(state: Dictionary, world: Dictionary) -> void:
	if state.rescue_active or state.companion_mode != BUBBLE:
		return
	state.rescue_active = 1
	state.rescue_mask = 0
	state.health_wait = 0
	state.bubble_bound_ticks = 0
	state.companion_vx = 0
	state.companion_vy = 0
	# The captors start above the reference screen's centre, which stays inside the map;
	# never a display-sized viewport.
	var centre_x := Screen.centre_x(state, world)
	var centre_y := Screen.centre_y(state, world)
	for index in 4:
		state["rescue_%d_x" % (index + 1)] = centre_x + [-120, -24, 24, 120][index] * S
		state["rescue_%d_y" % (index + 1)] = centre_y - 304 * S


static func _rescue_step(state: Dictionary) -> void:
	for index in 4:
		if state.rescue_mask & (1 << index):
			continue
		var x_key := "rescue_%d_x" % (index + 1)
		var y_key := "rescue_%d_y" % (index + 1)
		var target_x: int = state.recovery_x + RESCUE_OFFSETS[index][0] * S
		var target_y: int = state.recovery_y + RESCUE_OFFSETS[index][1] * S
		var dx: int = target_x - state[x_key]
		var dy: int = target_y - state[y_key]
		# Normalize before squaring. Large saved positions must not overflow int64.
		var divisor := maxi(1, maxi(absi(dx), absi(dy)) / 1000000 + 1)
		var nx := dx / divisor
		var ny := dy / divisor
		var distance := maxi(1, _root(nx * nx + ny * ny))
		if divisor == 1 and distance <= 1024 * 60:
			state[x_key] = target_x
			state[y_key] = target_y
		else:
			state[x_key] += nx * 1024 * 60 / distance
			state[y_key] += ny * 1024 * 60 / distance
		if _rescuer_overlaps(state[x_key] - state.recovery_x, state[y_key] - state.recovery_y):
			state[x_key] = target_x
			state[y_key] = target_y
			state.rescue_mask |= 1 << index
	if state.rescue_mask == 15:
		state.companion_mode = TAKEN
		state.rescue_ticks = 90


static func _phase_step(
	state: Dictionary, world: Dictionary, reset_map: Callable, change_map: Callable
) -> bool:
	if state.life_phase == RESPAWN:
		return _respawn(state, world, reset_map, change_map)
	if state.life_phase == COMPLETE:
		return false
	state.life_ticks = maxi(0, state.life_ticks - 1)
	match state.life_phase:
		REJOIN:
			var age: int = REJOIN_STEPS - state.life_ticks
			var across := mini(age, 48)
			state.recovery_x = (
				state.companion_from_x + (_anchor_x(state) - state.companion_from_x) * across / 48
			)
			if age <= 24:
				state.recovery_y = state.companion_from_y - 96 * S * age * (48 - age) / 576
			else:
				# The drop starts one step after the rise ends and holds at the saddle.
				var leg := clampi(age - 25, 0, 24)
				state.recovery_y = (
					state.companion_from_y
					- 96 * S
					+ (_anchor_y(state) - state.companion_from_y + 96 * S) * leg * leg / 576
				)
			if state.life_ticks == 0:
				state.separated = 0
				state.companion_mode = ATTACHED
				state.separation_grace = 30
				state.life_phase = PLAY
				_attach_position(state)
				Sound.player(state)
		DEAD:
			if state.life_ticks == 0:
				state.life_phase = FADE_OUT
				state.life_ticks = DEATH_FADE
		FADE_OUT:
			if state.life_ticks == 0:
				state.life_phase = RESPAWN
				return _respawn(state, world, reset_map, change_map)
		FADE_IN:
			if state.life_ticks == 0:
				state.life_phase = PLAY
		CHECKPOINT:
			_checkpoint_step(state)
		GOAL:
			var age: int = mini(60, 180 - state.life_ticks)
			var blend := age * (120 - age)
			state.x = state.goal_from_x + (state.goal_x - state.goal_from_x) * blend / 3600
			state.y = state.goal_from_y + (state.goal_y - state.goal_from_y) * blend / 3600
			state.camera_x = state.x
			state.camera_y = state.y - 28 * S
			_attach_position(state)
			if state.life_ticks == 0:
				state.goal_reached = 1
				state.life_phase = COMPLETE
	return false


static func _checkpoint_step(state: Dictionary) -> void:
	if state.life_ticks:
		return
	if state.checkpoint_awards > 0 and state.health < 30:
		state.health += 1
		state.checkpoint_awards -= 1
		if state.checkpoint_awards > 0 and state.health < 30:
			state.life_ticks = 6
			return
		state.checkpoint_awards = 0
		state.checkpoint_health = maxi(10, state.health)
		state.life_ticks = 45
	else:
		state.life_phase = PLAY


static func _respawn(
	state: Dictionary, world: Dictionary, reset_map: Callable, change_map: Callable
) -> bool:
	var map_index: int = state.checkpoint_map if state.checkpoint_id else state.run_spawn_map
	var x: int = state.checkpoint_x if state.checkpoint_id else state.run_spawn_x
	var y: int = state.checkpoint_y if state.checkpoint_id else state.run_spawn_y
	if map_index != int(state.get("map_index", 1)):
		if not change_map.is_valid():
			return false
		var changed: Variant = change_map.call(state, world, map_index, x, y)
		if changed is bool and not changed:
			return false
	else:
		if not reset_map.is_valid():
			return false
		reset_map.call(state, world, true)
	var hits: int = state.hits
	var quick: int = state.quick_death
	for field: Array in PLAYER_FIELDS:
		state[field[0]] = field[1]
	state.hits = hits
	state.quick_death = quick
	for name: String in [
		"swimming",
		"water_wait",
		"water_phase",
		"water_deep",
		"captured_by",
		"support_bridge",
		"on_floor"
	]:
		if state.has(name):
			state[name] = 0
	state.x = x
	state.y = y
	state.vx = 0
	state.vy = 0
	state.facing = state.run_spawn_facing
	state.camera_x = x
	state.camera_y = y - 28 * S
	state.goal_reached = 0
	state.movement = 0
	state.redcoins = state.checkpoint_redcoins
	state.flowers = state.checkpoint_flowers
	state.health = state.checkpoint_health if state.checkpoint_id else 10
	state.play_ticks = state.checkpoint_play_ticks
	state.life_phase = FADE_IN
	state.life_ticks = RESTART_STEPS
	_attach_position(state)
	return true


static func valid_state(state: Dictionary) -> bool:
	for list: Array in [PLAYER_FIELDS, LEVEL_FIELDS]:
		for field: Array in list:
			if not state.has(field[0]) or not state[field[0]] is int:
				return false
	if (
		state.life_phase < PLAY
		or state.life_phase > COMPLETE
		or state.companion_mode < ATTACHED
		or state.companion_mode > TAKEN
	):
		return false
	for field: String in [
		"x",
		"y",
		"camera_x",
		"camera_y",
		"recovery_x",
		"recovery_y",
		"companion_from_x",
		"companion_from_y",
		"companion_dx",
		"bubble_bound_from_x",
		"bubble_bound_to_x",
		"goal_from_x",
		"goal_from_y",
		"goal_x",
		"goal_y",
		"run_spawn_x",
		"run_spawn_y",
		"checkpoint_x",
		"checkpoint_y",
		"rescue_1_x",
		"rescue_1_y",
		"rescue_2_x",
		"rescue_2_y",
		"rescue_3_x",
		"rescue_3_y",
		"rescue_4_x",
		"rescue_4_y"
	]:
		var coordinate := int(state.get(field, 0))
		if coordinate < -MAX_POSITION or coordinate > MAX_POSITION:
			return false
	if state.health < 0 or state.health > 30 or state.health_wait < 0 or state.health_wait > 120:
		return false
	if (
		state.hurt < 0
		or state.hurt > MAX_HURT
		or state.invulnerable < 0
		or state.invulnerable > IMMUNITY
	):
		return false
	if (
		state.hurt_phase < HURT_NONE
		or state.hurt_phase > HURT_LOOK_AROUND
		or (state.hurt_phase != HURT_NONE and state.hurt == 0)
	):
		return false
	if (
		state.hurt_deceleration not in [0, 128, 648, 1296]
		or state.life_ticks < 0
		or state.life_ticks > 240
	):
		return false
	if state.bubble_bound_ticks < 0 or state.bubble_bound_ticks > 6:
		return false
	if (
		state.recovery_delay < 0
		or state.recovery_delay > 36
		or state.separation_grace < 0
		or state.separation_grace > 30
	):
		return false
	if (
		state.rescue_mask < 0
		or state.rescue_mask > 15
		or state.rescue_ticks < 0
		or state.rescue_ticks > 90
	):
		return false
	if (
		state.checkpoint_awards < 0
		or state.checkpoint_awards > 30
		or state.checkpoint_health < 10
		or state.checkpoint_health > 30
	):
		return false
	if (
		state.death_cause < NONE
		or state.death_cause > QUICK
		or state.companion_direction not in [-1, 1]
	):
		return false
	for name: String in ["separated", "quick_death", "rescue_active", "life_ready"]:
		if state[name] not in [0, 1]:
			return false
	for name: String in [
		"checkpoint_id",
		"coins",
		"redcoins",
		"flowers",
		"checkpoint_redcoins",
		"checkpoint_flowers",
		"hits",
		"play_ticks",
		"attempt_ticks",
		"total_play_ticks",
		"checkpoint_play_ticks",
		"companion_age"
	]:
		if state[name] < 0:
			return false
	var map_count := int(state.get("map_count", maxi(state.run_spawn_map, state.checkpoint_map)))
	if (
		state.run_spawn_map < 1
		or state.run_spawn_map > map_count
		or state.checkpoint_map < 1
		or state.checkpoint_map > map_count
		or state.run_spawn_facing not in [-1, 1]
	):
		return false
	if (state.companion_mode == ATTACHED) != (state.separated == 0):
		return false
	if (state.life_phase == REJOIN) != (state.companion_mode == RETURNING):
		return false
	if state.life_phase == PLAY and state.life_ticks != 0:
		return false
	if (state.life_phase == COMPLETE) != bool(state.get("goal_reached", 0)):
		return false
	if (
		state.companion_age > 300
		or state.companion_vx < -48 * 60
		or state.companion_vx > 48 * 60
		or state.companion_vy < -192 * 60
		or state.companion_vy > 192 * 60
	):
		return false
	if state.companion_mode == TAKEN and (not state.rescue_active or state.rescue_mask != 15):
		return false
	if state.checkpoint_id and state.checkpoint_map == int(state.get("map_index", 1)):
		var found := false
		for entity: Dictionary in state.get("entities", []):
			if (
				int(entity.get("source_index", -1)) + 1 == state.checkpoint_id
				and entity.get("code", "o6") == "o6"
			):
				found = true
		if not found:
			return false
	return true


static func _anchor_x(state: Dictionary) -> int:
	return int(state.x) - int(state.facing) * 10 * S


static func _anchor_y(state: Dictionary) -> int:
	return int(state.y) - 24 * S


static func _attach_position(state: Dictionary) -> void:
	state.recovery_x = _anchor_x(state)
	state.recovery_y = _anchor_y(state)


## The bubble's body against terrain: its octagon inside the box that bounds it.
static func _bubble_body() -> Array:
	if _bubble_body_cache.is_empty():
		_bubble_body_cache = BUBBLE_BOX.duplicate()
		_bubble_body_cache.append(_bubble_points())
		_bubble_body_cache.make_read_only()
	return _bubble_body_cache


static func _bubble_points() -> PackedInt64Array:
	return _points(BUBBLE_POINTS)


static func _points(raw: Array) -> PackedInt64Array:
	var points := PackedInt64Array()
	for coordinate: int in raw:
		points.append(coordinate * S)
	return points


static func _rescuer_overlaps(dx: int, dy: int) -> bool:
	if dx < -43 * S or dx > 42 * S or dy < -83 * S or dy > 24 * S:
		return false
	var bubble := _bubble_points()
	var rescuer := _points(RESCUER_POINTS)
	if (
		Polygon.contains_point(bubble, rescuer[0] + dx, rescuer[1] + dy)
		or Polygon.contains_point(rescuer, bubble[0] - dx, bubble[1] - dy)
	):
		return true
	for a in range(0, bubble.size(), 2):
		var next_a := (a + 2) % bubble.size()
		for b in range(0, rescuer.size(), 2):
			var next_b := (b + 2) % rescuer.size()
			if Polygon.segments_meet(
				bubble[a],
				bubble[a + 1],
				bubble[next_a],
				bubble[next_a + 1],
				rescuer[b] + dx,
				rescuer[b + 1] + dy,
				rescuer[next_b] + dx,
				rescuer[next_b + 1] + dy
			):
				return true
	return false


static func _plus_one(value: int) -> int:
	return value + 1 if value < MAX_COUNT else MAX_COUNT


static func _root(value: int) -> int:
	var low := 0
	var high := mini(value, 1000000000)
	while low < high:
		var middle := (low + high + 1) / 2
		if middle <= value / middle:
			low = middle
		else:
			high = middle - 1
	return low
