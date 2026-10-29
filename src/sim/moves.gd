extends RefCounted
## Player motion, actions and integer requests for future object consumers.
## Requests are latched by serial, not transient callbacks or unsaved queues.
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Water = preload("res://src/sim/water.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Tongue = preload("res://src/sim/move_tongue.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Sound = preload("res://src/sim/sound_events.gd")
const S := preload("res://src/sim/units.gd").SCALE
const INPUT_MASK := InputBits.MASK
const ACCELERATION := 512
const DECELERATION := 1296
const GRAVITY := 2048
const MAX_SPEED := 400 * 60
const MAX_FALL := 704 * 60
const JUMP_SPEED := 776 * 60
## Flutter lift: the end timer (0.66 s, 0.82 s boosted) is checked after the frame's
## damping, so the lift damps on one more step than its whole-step length.
const FLUTTER_TICKS := 41
const BOOSTED_FLUTTER_TICKS := 51
## Flutter delay after a cancel: a 0.266 s timer still counts as running on the step it
## expires, so the next flutter can start 17 steps after the cancel.
const FLUTTER_COOLDOWN := 17
## A flutter that lands lifts the body this far before the next move.
const FLUTTER_LANDING_LIFT := 2 * S
const NORMAL_BOX := [-12 * S, -56 * S, 12 * S, 0]
const NORMAL := 0
const POUND_START := 1
const POUND_FALL := 2
const POUND_LAND := 3
const TONGUE := 4
const SPIT := 5
const LAY := 6
const EMIT := 7
const TOSS := 8
const HEAD_BUMP := 9
const LAND := 10
const SWALLOW := 11
## Actions whose start the original voices with a player sound effect.
const SOUNDING_ACTIONS := [POUND_START, POUND_LAND, TONGUE, TOSS, HEAD_BUMP]
const TONGUE_NONE := 0
const TONGUE_OUT := 1
const TONGUE_BLOCKED := 2
const TONGUE_FAILED := 3
const REQUEST_EGG := Requests.EGG
const REQUEST_SPIT := Requests.SPIT
const REQUEST_SEED := Requests.SEED
const REQUEST_HEAT := Requests.HEAT
const REQUEST_COLD := Requests.COLD
const REQUEST_CONSUME := Requests.CONSUME
const REQUEST_STORED_EGG := Requests.STORED_EGG
const SEED := 1
const HEAT := 2
const COLD := 3
const PLAYER_FIELDS := [
	["move_action", NORMAL],
	["move_action_tick", 0],
	["move_action_wet", 0],
	["move_duck", 0],
	["move_look", 0],
	["move_posture_tick", 0],
	["move_turn", 0],
	["move_turn_ticks", 0],
	["move_push", 0],
	["move_pound_delay", 0],
	["move_impact", 0],
	["move_impact_x", 0],
	["move_impact_y", 0],
	["move_aim", 0],
	["move_aim_angle", 45000],
	["move_aim_dir", -1],
	["move_aim_lock", 0],
	["move_aim_up", 0],
	["move_eggs", 0],
	["move_held_id", 0],
	["move_digest", 0],
	["move_instant", 0],
	["move_digest_ticks", 0],
	["move_ammo", 0],
	["move_ammo_count", 0],
	["move_held_speed", 256 * 60],
	["move_tongue_axis", 0],
	["move_tongue_length", 16 * S],
	["move_tongue_phase", TONGUE_NONE],
	["move_tongue_block_tick", 0],
	["move_tongue_hold", 16 * S],
	["move_swallow_queue", 0],
	["move_dive", 0],
	["move_water_jump", 0],
	["move_water_transition", 0],
	["move_gravity_tick", 0],
	["move_snow", 0],
	["move_flow", 0],
	["move_flutter_flow", 0],
	["move_emit_serial", 0],
	["move_emit_kind", 0],
	["move_emit_item", 0],
	["move_emit_x", 0],
	["move_emit_y", 0],
	["move_emit_angle", 0],
	["move_emit_vx", 0],
	["move_emit_vy", 0],
	["move_emit_1_serial", 0],
	["move_emit_1_kind", 0],
	["move_emit_1_item", 0],
	["move_emit_1_x", 0],
	["move_emit_1_y", 0],
	["move_emit_1_angle", 0],
	["move_emit_1_vx", 0],
	["move_emit_1_vy", 0],
	["move_emit_2_serial", 0],
	["move_emit_2_kind", 0],
	["move_emit_2_item", 0],
	["move_emit_2_x", 0],
	["move_emit_2_y", 0],
	["move_emit_2_angle", 0],
	["move_emit_2_vx", 0],
	["move_emit_2_vy", 0],
	["move_emit_3_serial", 0],
	["move_emit_3_kind", 0],
	["move_emit_3_item", 0],
	["move_emit_3_x", 0],
	["move_emit_3_y", 0],
	["move_emit_3_angle", 0],
	["move_emit_3_vx", 0],
	["move_emit_3_vy", 0],
	["move_spread", 0],
	# Horizontal speed after the player's own move, before object contacts change it. The
	# snow brake for the next step is chosen from it.
	["move_brake_vx", 0],
	# A jump that started after the move (landing with a buffered jump) still counts as a
	# jump for the next move, which therefore adds gravity.
	["move_jump_carry", 0],
]


static func initialize(state: Dictionary) -> void:
	# The composed state schema normally supplies these. This also permits pure callers.
	for field: Array in PLAYER_FIELDS:
		if not state.has(field[0]):
			state[field[0]] = field[1]


static func reset(state: Dictionary) -> void:
	for field: Array in PLAYER_FIELDS:
		state[field[0]] = field[1]
	state.flutter_remaining = 0
	state.flutter_cooldown = 0
	state.flutter_ready = 1
	state.boosted_flutter = 0
	state.jump_buffer = 0


static func interrupt(state: Dictionary) -> void:
	initialize(state)
	state.move_action = NORMAL
	state.move_action_tick = 0
	state.move_aim = 0
	state.move_duck = 0
	state.move_look = 0
	state.move_turn = 0
	state.move_turn_ticks = 0
	state.move_tongue_length = 16 * S
	state.move_tongue_phase = TONGUE_NONE
	state.move_swallow_queue = 0
	state.move_gravity_tick = 0
	state.jump_buffer = 0
	cancel_flutter(state)


static func advance(
	state: Dictionary, input: int, world: Dictionary, pressed: int, released: int
) -> bool:
	initialize(state)
	state.move_pound_delay = maxi(0, state.move_pound_delay - 1)
	state.flutter_cooldown = maxi(0, state.flutter_cooldown - 1)
	_tick_action(state, input)
	state.move_turn_ticks = maxi(0, state.move_turn_ticks - 1)
	if not state.move_turn_ticks:
		state.move_turn = 0
	if state.hurt:
		interrupt(state)
	var bounds := player_box(state)
	var can_move := Collision.prepare(state, world, bounds)
	# Rules before the move see the floor only once the body stands on it (no vertical
	# speed). A body still falling onto the floor settles there just before the move.
	var support := Collision.track_floor(state, world, bounds, false)
	state.on_floor = int(support != 0 and state.vy == 0)
	var was_grounded: bool = state.on_floor != 0
	var carried_jump: bool = state.move_jump_carry != 0
	state.move_jump_carry = 0
	_snow(state, world, bounds)
	state.jump_buffer = 6 if pressed & InputBits.JUMP else maxi(0, state.jump_buffer - 1)
	if state.frame <= 1:
		state.flutter_ready = 1
	# Releasing jump during a flutter still damps this step; the flutter ends after that.
	var release_flutter := false
	if released & InputBits.JUMP:
		if state.flutter_remaining:
			release_flutter = true
		elif not state.flutter_ready:
			state.boosted_flutter = 0
		state.flutter_ready = 1
		if state.vy < 0:
			state.vy /= 4
	elif not input & InputBits.JUMP and not state.flutter_remaining and not state.flutter_ready:
		state.flutter_ready = 1
		state.boosted_flutter = 0
	var was_swimming: bool = state.swimming != 0
	var water := Water.prepare(
		state, input, world, pressed, state.move_action not in [TONGUE, SPIT, EMIT]
	)
	var bob: int = water.bob
	if water.jump:
		jump(state)
	if state.swimming:
		cancel_flutter(state)
		state.move_aim = 0
		if not was_swimming and state.move_action in [POUND_START, POUND_FALL, POUND_LAND]:
			_set_action(state, NORMAL)
	if not state.hurt:
		_actions(state, input, pressed, world)
	_posture(state, input, world)
	bounds = player_box(state)
	var jumping := carried_jump
	if (
		not state.swimming
		and state.on_floor
		and state.jump_buffer
		and input & InputBits.JUMP
		and state.move_action not in [POUND_START, POUND_FALL, POUND_LAND]
		and not Collision.overlaps(state, world, NORMAL_BOX, 0, -S)
	):
		jump(state)
		jumping = true
		bounds = player_box(state)
	var lift := _flutter(state, input)
	if release_flutter:
		state.flutter_remaining = 0
		state.flutter_cooldown = FLUTTER_COOLDOWN
		state.move_flutter_flow = 0
		state.move_gravity_tick = 0
		state.boosted_flutter = 0
	var direction := int(bool(input & InputBits.RIGHT)) - int(bool(input & InputBits.LEFT))
	if state.move_duck or state.move_action in [POUND_START, POUND_FALL, POUND_LAND]:
		direction = 0
	if state.move_action == POUND_START:
		state.vx = 0
		state.vy = 0
	var speed := 200 * 60 if state.swimming else (336 * 60 if state.move_snow else MAX_SPEED)
	var facing_locked: bool = (
		state.move_aim
		or state.move_duck
		or state.move_action in [TONGUE, SPIT, EMIT, POUND_START, POUND_FALL, POUND_LAND]
	)
	if (
		was_grounded
		and state.move_snow
		and not facing_locked
		and input & (InputBits.LEFT | InputBits.RIGHT)
	):
		state.facing = 1 if input & InputBits.RIGHT else -1
	var deceleration := _deceleration(state, input)
	var acceleration := 192 if state.move_snow else ACCELERATION
	if state.move_action in [TONGUE, SPIT, EMIT, LAY]:
		state.vx = clampi(state.vx, -200 * 60, 200 * 60)
	if (
		direction
		and not state.move_duck
		and state.move_action not in [POUND_START, POUND_FALL, POUND_LAND]
	):
		acceleration *= direction
		if state.vx * direction < 0:
			acceleration += direction * deceleration
	else:
		acceleration = 0
	if (
		was_grounded
		and not state.move_snow
		and not state.move_aim
		and state.move_action == NORMAL
		and direction * state.vx < -320 * 60
	):
		state.move_turn = direction
		state.move_turn_ticks = 30
	if lift and not Collision.overlaps(state, world, bounds, 0, -FLUTTER_LANDING_LIFT):
		# After the landing step's other rules: the next move starts from the air.
		state.y -= FLUTTER_LANDING_LIFT
		support = Collision.floor_at(state, world, bounds)
	Collision.settle_floor(state, world, bounds, support)
	var dx := clampi(state.vx + acceleration / 2, -speed, speed) if state.vx else 0
	var gravity := _gravity(state)
	var dy := (
		mini(state.vy + gravity / 2, 2 * MAX_FALL if state.move_action == POUND_FALL else MAX_FALL)
		if state.vy
		else 0
	)
	if state.move_action == POUND_START:
		dx = 0
		dy = 0
	if can_move:
		Collision.horizontal(state, world, bounds, dx, support, jumping, JUMP_SPEED)
	var vertical := dy + bob
	var moved := Collision.vertical(state, world, bounds, vertical, support) if can_move else 0
	var floor := Collision.floor_at(state, world, bounds)
	# Landed: the move hit the floor, or the body did not move vertically and stands on one.
	# A free fall that ends just above a floor lands on the next step.
	state.on_floor = int(
		can_move and ((vertical > 0 and moved != vertical) or (vertical == 0 and floor != 0))
	)
	state.support_bridge = maxi(0, floor) if state.on_floor else 0
	if moved != vertical and vertical < 0 and state.move_action == NORMAL:
		_set_action(state, HEAD_BUMP)
	if state.on_floor:
		state.vy = 0
		state.boosted_flutter = 0
		# A flutter that lands ends on the next step (_flutter); its delay timer keeps running.
		state.move_gravity_tick = 0
		if state.move_action == POUND_FALL:
			_set_action(state, POUND_LAND)
			state.move_impact += 1
			state.move_impact_x = state.x
			state.move_impact_y = state.y
		elif not was_grounded and state.move_action == NORMAL:
			_set_action(state, LAND)
	elif state.move_action != POUND_START and (support == 0 or jumping):
		# A step that starts on a floor adds no gravity unless it jumps, even when the
		# body leaves the floor during the move (walking off a ledge, a ground knockback).
		state.vy = mini(
			state.vy + gravity, 2 * MAX_FALL if state.move_action == POUND_FALL else MAX_FALL
		)
	if not direction:
		state.vx = approach(state.vx, 0, deceleration)
	state.vx = clampi(state.vx + acceleration, -speed, speed)
	if state.vx and Collision.by_wall(state, world, bounds, 1 if state.vx > 0 else -1):
		state.vx = 0
	if state.move_turn and 0 < state.vx * state.move_turn and state.vx * state.move_turn < 64 * 60:
		state.vx = state.move_turn * 96 * 60
		state.move_turn = 0
		state.move_turn_ticks = 0
	if (was_grounded or state.swimming) and not facing_locked and not state.move_snow and state.vx:
		state.facing = 1 if state.vx > 0 else -1
	if (
		state.on_floor
		and state.jump_buffer
		and input & InputBits.JUMP
		and state.move_action not in [POUND_START, POUND_FALL, POUND_LAND]
		and not state.swimming
	):
		if not Collision.overlaps(state, world, NORMAL_BOX, 0, -S):
			jump(state)
			state.move_jump_carry = 1
	state.x = clampi(state.x, 12 * S, world.width - 12 * S)
	state.move_brake_vx = state.vx
	Water.finish(state, world, player_box(state))
	if state.move_action == TONGUE:
		_tongue(state, world)
	return state.y > world.height + 96 * S


static func finish(state: Dictionary, input: int, world: Dictionary) -> void:
	initialize(state)
	var direction := int(bool(input & InputBits.RIGHT)) - int(bool(input & InputBits.LEFT))
	state.move_push = int(
		(
			state.on_floor
			and direction != 0
			and state.vx == 0
			and Collision.by_wall(state, world, player_box(state), direction)
		)
	)
	state.movement = 0 if state.vx == 0 else (2 if absi(state.vx) >= 320 * 60 else 1)
	if not state.on_floor:
		state.movement = 3 if state.vy < 0 else 4
		# A flutter that just landed ends on the next step and shows the ground pose.
		if state.flutter_remaining:
			state.movement = 6


static func jump(state: Dictionary) -> void:
	Sound.player(state)
	# The jump pose does not support a flutter.
	cancel_flutter(state)
	state.vy = -JUMP_SPEED
	state.on_floor = 0
	state.jump_buffer = 0
	state.flutter_ready = 1
	state.move_pound_delay = 6
	state.move_duck = 0
	state.move_look = 0
	state.move_gravity_tick = 0
	if state.move_action in [LAND, HEAD_BUMP]:
		_set_action(state, NORMAL)


static func bounce(state: Dictionary, velocity: int, input: int) -> bool:
	initialize(state)
	if velocity >= 0 or velocity < -9223372036854775807 + 384 * 60:
		return false
	if state.move_action in [POUND_START, POUND_FALL, POUND_LAND]:
		state.move_pound_delay = 6
	if state.move_action != TONGUE:
		_set_action(state, NORMAL)
		cancel_flutter(state)
	state.vy = velocity - (384 * 60 if input & InputBits.JUMP else 0)
	state.on_floor = 0
	state.support_bridge = 0
	state.jump_buffer = 0
	state.flutter_ready = 1
	state.boosted_flutter = 1
	state.move_gravity_tick = 0
	return true


## How far below the map bottom the player's feet may fall before the pit takes it: the
## height of the pose the player shows. Airborne poses use the original's frame heights
## (fall, jump, flutter, hurt; empty or full mouth). Other poses keep the fixed 62 px.
## Pack independent.
static func pit_height(state: Dictionary) -> int:
	if state.get("on_floor", 0) or state.get("swimming", 0):
		return 62 * S
	if state.get("move_action", NORMAL) not in [NORMAL, LAND]:
		return 62 * S
	var full: bool = state.get("move_held_id", 0) != 0 or state.get("move_ammo_count", 0) != 0
	if state.get("hurt", 0):
		return 64 * S
	if state.get("flutter_remaining", 0):
		return (70 if full else 68) * S
	if state.get("vy", 0) < 0:
		return (72 if full else 66) * S
	return (64 if full else 66) * S


static func player_box(state: Dictionary) -> Array:
	var full: bool = state.get("move_held_id", 0) != 0 or state.get("move_ammo_count", 0) != 0
	var action: int = state.get("move_action", NORMAL)
	var tick: int = state.get("move_action_tick", 0)
	var height := 56
	var bottom := 0
	if state.get("move_duck", 0):
		var heights := [56, 56, 32] if full else [52, 48, 32]
		height = heights[mini(2, state.get("move_posture_tick", 0) * 24 / 60)]
	elif action in [POUND_START, POUND_FALL]:
		var frame := 6 if action == POUND_FALL else mini(6, tick * 36 / 60)
		height = ([52, 52, 56, 50, 48, 58, 54] if full else [52, 52, 56, 50, 48, 54, 50])[frame]
		bottom = [0, 4, 2, 0, 0, 2, 0][frame] if full else 0
	elif action == POUND_LAND:
		height = [44, 38, 40][mini(2, tick * 16 / 60)] if full else (40 if tick < 4 else 36)
	elif action == TONGUE:
		height = 60 if state.move_tongue_axis else 50
	elif action == SPIT:
		height = (54 if state.move_action_wet else 56) if state.move_tongue_axis else 50
	elif action == EMIT:
		height = 56 if state.move_tongue_axis else (50 if state.swimming else 54)
	elif action == HEAD_BUMP and tick * 24 / 60 == 1:
		return [-14 * S, -56 * S, 10 * S, 0]
	elif action == NORMAL and state.swimming:
		if state.get("move_water_transition", 0):
			height = [54, 50, 54][mini(2, (9 - state.move_water_transition) * 20 / 60)]
		elif state.get("move_dive", 0):
			height = 42 if state.vx else 54
			bottom = 14 if state.vx else 0
	return [-12 * S, -height * S, 12 * S, bottom * S]


static func _posture(state: Dictionary, input: int, world: Dictionary) -> void:
	var previous_duck: int = state.move_duck
	var previous_look: int = state.move_look
	var down := bool(input & InputBits.DOWN)
	var duck: bool = (
		state.on_floor
		and down
		and not state.swimming
		and not state.move_turn
		and state.move_action in [NORMAL, HEAD_BUMP, TOSS]
	)
	if state.move_duck and not duck:
		# Keep the compact collider until standing is safe; never push through a low roof.
		duck = Collision.overlaps(state, world, NORMAL_BOX)
	state.move_duck = int(duck)
	if duck:
		state.vx = 0
		state.move_aim = 0
		if state.move_action in [HEAD_BUMP, TOSS]:
			_set_action(state, NORMAL)
	state.move_look = int(
		(
			state.on_floor
			and not down
			and input & InputBits.UP
			and state.vx == 0
			and state.move_action in [NORMAL, LAY, SWALLOW, HEAD_BUMP]
			and not state.move_aim
			and not state.move_turn
			and not state.swimming
		)
	)
	if state.move_look and state.move_action != NORMAL:
		_set_action(state, NORMAL)
	if (
		state.move_duck == previous_duck
		and state.move_look == previous_look
		and (duck or state.move_look)
	):
		state.move_posture_tick = mini(9, state.move_posture_tick + 1)
	else:
		state.move_posture_tick = 0


static func _deceleration(state: Dictionary, input: int) -> int:
	if state.hurt or state.swimming:
		return state.hurt_deceleration
	if not state.on_floor and not state.swimming:
		return DECELERATION if input & InputBits.LEFT and input & InputBits.RIGHT else 0
	# Snow brakes lightly while the body slides against its facing (a reversal or a
	# shove). The brake is chosen from the speed before the last object contact.
	if state.move_snow and state.facing * state.move_brake_vx < 0:
		return 256
	return DECELERATION


static func _snow(state: Dictionary, world: Dictionary, bounds: Array) -> void:
	var found := false
	var offset := 2 if state.move_snow else 4
	for layer: Dictionary in world.layers:
		if (
			layer.get("name", "") == "snow64"
			and World.layer_overlaps(
				layer,
				state.x + bounds[0],
				state.y + bounds[1] + offset * S,
				state.x + bounds[2],
				state.y + bounds[3] + offset * S
			)
		):
			found = true
			break
	state.move_snow = int(found and not state.swimming)


static func _gravity(state: Dictionary) -> int:
	if state.swimming or state.flutter_remaining or state.move_action == POUND_START:
		return 0
	if state.move_action == POUND_FALL:
		return 2 * GRAVITY
	if state.move_gravity_tick and (state.move_action != NORMAL or state.move_aim):
		state.move_gravity_tick = 0
	if state.move_gravity_tick:
		var tick: int = state.move_gravity_tick - 1
		state.move_gravity_tick = tick + 2 if tick < 23 else 0
		return 1024 + 1024 * (48 * tick - tick * tick) / (24 * 24)
	return GRAVITY


static func cancel_flutter(state: Dictionary) -> void:
	if state.flutter_remaining:
		state.flutter_cooldown = FLUTTER_COOLDOWN
	state.flutter_remaining = 0
	state.move_flutter_flow = 0


## One flutter step. Returns true when a flutter that landed ends here; the caller then
## lifts the body before the move.
static func _flutter(state: Dictionary, input: int) -> bool:
	if state.swimming or state.move_action in [POUND_START, POUND_FALL, POUND_LAND]:
		return false
	if state.flutter_remaining and state.on_floor:
		state.vx = clampi(state.vx, -256 * 60, 256 * 60)
		cancel_flutter(state)
		return true
	if (
		not state.on_floor
		and not state.flutter_remaining
		and state.flutter_ready
		and state.flutter_cooldown == 0
		and input & InputBits.JUMP
		and state.vy > 192 * 60
	):
		state.flutter_remaining = BOOSTED_FLUTTER_TICKS if state.boosted_flutter else FLUTTER_TICKS
		state.flutter_ready = 0
		Sound.player(state)
		state.vy = mini(state.vy, 392 * 60)
		state.move_gravity_tick = 0
		if state.move_action == HEAD_BUMP:
			_set_action(state, NORMAL)  # The flutter pose replaces the head bump pose.
	if not state.flutter_remaining:
		return false
	if state.move_flow != state.move_flutter_flow:
		state.flutter_remaining = maxi(
			1, state.flutter_remaining + (21 if state.move_flow else -21)
		)
		state.move_flutter_flow = state.move_flow
	# Fixed rational coefficients for the two supported contact states at 60 Hz.
	var coefficient := 50569 if state.move_flutter_flow else 37649
	state.vy += ((-424 if state.boosted_flutter else -264) * 60 - state.vy) * coefficient / 1000000
	state.vx = clampi(state.vx, -256 * 60, 256 * 60)
	state.flutter_remaining -= 1
	if state.flutter_remaining == 0:
		state.flutter_cooldown = FLUTTER_COOLDOWN
		state.move_gravity_tick = 1
		state.move_flutter_flow = 0
	return false


static func _set_action(state: Dictionary, action: int) -> void:
	# Starting a pound, landing one, the tongue, a toss or a head bump makes a sound.
	if action != state.move_action and action in SOUNDING_ACTIONS:
		Sound.player(state)
	if state.move_action == TONGUE and action != TONGUE:
		state.move_tongue_phase = TONGUE_NONE
	state.move_action = action
	state.move_action_tick = 0
	state.move_action_wet = state.swimming


static func _tick_action(state: Dictionary, input: int) -> void:
	if state.move_digest_ticks:
		state.move_digest_ticks -= 1
		if not state.move_digest_ticks:
			state.move_eggs = mini(6, state.move_eggs + 1)
			_emit(state, REQUEST_STORED_EGG, 0, state.x, state.y - 16 * S, 0)
	if state.move_action != EMIT:
		state.move_spread = 0
	if state.move_action != NORMAL or state.move_aim:
		state.move_action_tick = mini(35, state.move_action_tick + 1)
	match state.move_action:
		POUND_START:
			if state.move_action_tick >= 24:
				_set_action(state, POUND_FALL)
				state.vy = 2 * GRAVITY * 60
		POUND_LAND:
			if not input & InputBits.DOWN:
				_set_action(state, NORMAL)
				state.move_pound_delay = 6
		TONGUE:
			var end_tick := 12
			if state.move_tongue_phase == TONGUE_FAILED:
				end_tick = 3 if state.move_action_wet else 5
			elif state.move_tongue_phase == TONGUE_BLOCKED:
				end_tick = 18 + state.move_tongue_block_tick
			if state.move_action_tick >= end_tick:
				_set_action(state, NORMAL)
				state.move_tongue_length = 16 * S
				if state.move_instant and state.move_held_id:
					_emit(state, REQUEST_CONSUME, state.move_held_id, state.x, state.y, 0)
					state.move_held_id = 0
					state.move_digest = 0
					state.move_instant = 0
					_set_action(state, SWALLOW)
				elif state.move_swallow_queue and state.move_digest and state.move_held_id:
					_begin_lay(state)
		SPIT, HEAD_BUMP:
			if state.move_action_tick >= 10:
				_set_action(state, NORMAL)
		LAND:
			if state.move_action_tick >= 4:
				_set_action(state, NORMAL)
		TOSS:
			if state.move_action_tick >= 13:
				_set_action(state, NORMAL)
		LAY:
			if state.move_action_tick >= 25:
				_set_action(state, NORMAL)
		SWALLOW:
			if state.move_action_tick >= 35:
				_set_action(state, NORMAL)
		EMIT:
			if state.move_ammo == SEED:
				if state.move_action_tick >= 4:
					if state.move_ammo_count:
						_emit_ammo(state)
					if input & InputBits.USE and state.move_ammo_count:
						state.move_action_tick = 0
					else:
						_set_action(state, NORMAL)
						state.move_spread = 0
			elif state.move_action_tick >= 30:
				_set_action(state, NORMAL)


static func _actions(state: Dictionary, input: int, pressed: int, world: Dictionary) -> void:
	if (
		input & InputBits.DOWN
		and not state.on_floor
		and not state.swimming
		and not state.move_pound_delay
		and not state.move_digest
		and state.move_action not in [TONGUE, LAY, POUND_START, POUND_FALL, POUND_LAND]
	):
		cancel_flutter(state)
		state.move_aim = 0
		_set_action(state, POUND_START)
		state.vx = 0
		state.vy = 0
		return
	if state.move_aim:
		if pressed & InputBits.USE or state.swimming or state.move_duck:
			state.move_aim = 0
			return
		if pressed & InputBits.THROW:
			var angle: int = (
				state.move_aim_angle if state.facing > 0 else 180000 - state.move_aim_angle
			)
			if angle > 180000:
				angle -= 360000
			_emit(state, REQUEST_EGG, 0, state.x, state.y - 32 * S, angle)
			state.move_eggs -= 1
			state.move_aim = 0
			_set_action(state, TOSS)
			return
		if pressed & InputBits.LOCK:
			state.move_aim_lock = 1 - state.move_aim_lock
		if input & InputBits.UP:
			state.move_aim_angle = -90000
			state.move_aim_up = 1
		elif state.move_aim_up:
			state.move_aim_up = 0
			state.move_aim_dir = 1
		elif not state.move_aim_lock:
			state.move_aim_angle += state.move_aim_dir * 2250
			if state.move_aim_angle <= -90000:
				state.move_aim_angle = -90000
				state.move_aim_dir = 1
			elif state.move_aim_angle >= 45000:
				state.move_aim_angle = 45000
				state.move_aim_dir = -1
	elif (
		pressed & InputBits.THROW
		and not pressed & InputBits.USE
		and not state.swimming
		and state.move_action not in [POUND_START, POUND_FALL, POUND_LAND, TONGUE]
	):
		if state.move_eggs:
			_set_action(state, NORMAL)
			state.move_aim = 1
			state.move_aim_angle = -90000 if input & InputBits.UP else 45000
			state.move_aim_dir = 1 if input & InputBits.UP else -1
			state.move_aim_lock = 0
			state.move_aim_up = int(bool(input & InputBits.UP))
			state.move_action_tick = 0
		elif state.move_action != TOSS:
			_set_action(state, TOSS)
		return
	if pressed & InputBits.DOWN and state.move_action == TONGUE:
		state.move_swallow_queue = 1
	if (
		pressed & InputBits.DOWN
		and state.move_held_id
		and state.move_digest
		and state.move_action != TONGUE
	):
		_begin_lay(state)
		return
	if (
		pressed & InputBits.USE
		and state.move_action not in [POUND_START, POUND_FALL, POUND_LAND, LAY, TONGUE, TOSS, EMIT]
		and not state.move_push
	):
		state.move_tongue_axis = int(bool(input & InputBits.UP))
		state.move_dive = 0
		state.move_water_transition = 0
		if state.move_ammo_count:
			_set_action(state, EMIT)
			if state.move_ammo != SEED:
				_emit_ammo(state)
		elif state.move_held_id:
			_set_action(state, SPIT)
			var mouth := Tongue.mouth(state, state.move_action == SPIT)
			var probe := Tongue.probe(state, state.move_action == SPIT)
			if not World.overlaps_box(world, probe[0], probe[1], probe[2], probe[3]):
				_emit(
					state,
					REQUEST_SPIT,
					state.move_held_id,
					mouth[0],
					mouth[1],
					-90000 if state.move_tongue_axis else (0 if state.facing > 0 else 180000),
					0 if state.move_tongue_axis else state.facing * state.move_held_speed,
					(-768 if state.move_tongue_axis else -256) * 60
				)
				_clear_food(state)
				state.flutter_ready = 1
		else:
			_set_action(state, TONGUE)
			state.move_tongue_length = 16 * S
			state.move_tongue_phase = TONGUE_OUT
			state.move_tongue_block_tick = 0
			state.move_tongue_hold = 16 * S
			state.move_swallow_queue = int(bool(pressed & InputBits.DOWN))
			var probe := Tongue.probe(state, state.move_action == SPIT)
			if World.overlaps_box(world, probe[0], probe[1], probe[2], probe[3]):
				state.move_tongue_phase = TONGUE_FAILED


static func _tongue(state: Dictionary, world: Dictionary) -> void:
	if state.move_tongue_phase == TONGUE_FAILED:
		return
	var tick: int = state.move_action_tick
	var reach := (120 if state.move_tongue_axis else 128) * S
	var desired := 16 * S + (reach - 16 * S) * (tick if tick < 6 else maxi(0, 12 - tick)) / 6
	if state.move_tongue_phase == TONGUE_BLOCKED:
		desired = state.move_tongue_hold
		if tick >= 18:
			desired = (
				24 * S
				+ (
					(state.move_tongue_hold - 24 * S)
					* maxi(0, state.move_tongue_block_tick - tick + 18)
					/ maxi(1, state.move_tongue_block_tick)
				)
			)
	if not state.move_held_id:
		var last_clear := mini(16 * S, desired)
		for candidate in range(last_clear, desired + S, S):
			var length := mini(candidate, desired)
			var box := Tongue.sensor_box(state, length)
			if World.overlaps_box(world, box[0], box[1], box[2], box[3]):
				desired = last_clear
				state.move_tongue_length = desired
				block_tongue(state)
				break
			last_clear = length
	state.move_tongue_length = desired


static func block_tongue(state: Dictionary) -> void:
	if state.get("move_action", NORMAL) == TONGUE and state.move_tongue_phase == TONGUE_OUT:
		state.move_tongue_phase = TONGUE_BLOCKED
		state.move_tongue_block_tick = mini(12, state.move_action_tick)
		state.move_tongue_hold = state.move_tongue_length


static func tongue_box(state: Dictionary) -> Array:
	if (
		state.get("move_action", NORMAL) != TONGUE
		or state.move_held_id
		or state.move_tongue_phase not in [TONGUE_OUT, TONGUE_BLOCKED]
	):
		return []
	return Tongue.sensor_box(state, state.move_tongue_length)


static func tongue_reach_box(state: Dictionary) -> Array:
	# Rescue uses the whole reach, while eating keeps the tip sensor.
	if (
		state.get("move_action", NORMAL) != TONGUE
		or state.move_tongue_phase not in [TONGUE_OUT, TONGUE_BLOCKED]
	):
		return []
	return Tongue.reach_box(state, state.move_tongue_length)


static func catch_item(
	state: Dictionary,
	entity_id: int,
	digestible := 1,
	ammo := 0,
	count := 0,
	instant := 0,
	toss_speed := 256 * 60
) -> bool:
	initialize(state)
	if (
		state.move_action != TONGUE
		or state.move_tongue_phase not in [TONGUE_OUT, TONGUE_BLOCKED]
		or state.move_held_id
		or entity_id <= 0
		or ammo < 0
		or ammo > COLD
		or count < 0
		or count > 60
		or (ammo == 0) != (count == 0)
		or toss_speed < 0
	):
		return false
	state.move_held_id = entity_id
	state.move_digest = int(digestible != 0)
	state.move_ammo = ammo
	state.move_ammo_count = count
	state.move_held_speed = toss_speed
	state.move_instant = int(instant != 0 or ammo != 0)
	return true


static func give_eggs(state: Dictionary, count: int) -> void:
	initialize(state)
	state.move_eggs = mini(6, state.move_eggs + clampi(count, 0, 6))


static func set_waterfall_contact(state: Dictionary, active: bool) -> void:
	initialize(state)
	state.move_flow = int(active)


static func _clear_food(state: Dictionary) -> void:
	state.move_held_id = 0
	state.move_digest = 0
	state.move_instant = 0
	state.move_ammo = 0
	state.move_ammo_count = 0
	state.move_held_speed = 256 * 60


static func _begin_lay(state: Dictionary) -> void:
	_emit(state, REQUEST_CONSUME, state.move_held_id, state.x, state.y, 0)
	_clear_food(state)
	state.move_aim = 0
	state.move_swallow_queue = 0
	state.move_digest_ticks = 18
	_set_action(state, LAY)


static func _emit_ammo(state: Dictionary) -> void:
	var kind: int = state.move_ammo
	var mouth := Tongue.ammo_mouth(state)
	var angle := -90000 if state.move_tongue_axis else (0 if state.facing > 0 else 180000)
	if kind == SEED:
		state.rng = (state.rng * 1103515245 + 12345) & 0x7fffffff
		angle += (state.rng * (2 * state.move_spread + 1) / 2147483648) - state.move_spread
		angle = (angle + 540000) % 360000 - 180000
		state.move_spread = mini(14000, state.move_spread + 2000)
	_emit(
		state,
		REQUEST_SEED if kind == SEED else (REQUEST_HEAT if kind == HEAT else REQUEST_COLD),
		0,
		mouth[0],
		mouth[1],
		angle
	)
	state.move_ammo_count = maxi(0, state.move_ammo_count - 1)
	if not state.move_ammo_count:
		state.move_digest = 0


static func _emit(
	state: Dictionary, kind: int, item: int, x: int, y: int, angle: int, vx := 0, vy := 0
) -> void:
	Requests.emit(state, kind, item, x, y, angle, vx, vy)


static func spawn_request(state: Dictionary) -> Dictionary:
	return Requests.latest(state)


static func spawn_requests(state: Dictionary, after_serial: int) -> Dictionary:
	return Requests.since(state, after_serial)


static func impact_request(state: Dictionary) -> Dictionary:
	if not state.get("move_impact", 0):
		return {}
	return {"serial": state.move_impact, "x": state.move_impact_x, "y": state.move_impact_y}


static func approach(value: int, target: int, amount: int) -> int:
	return mini(value + amount, target) if value < target else maxi(value - amount, target)


static func valid_state(state: Dictionary) -> bool:
	for field: Array in PLAYER_FIELDS:
		if not state.get(field[0]) is int:
			return false
	for name: String in [
		"move_duck",
		"move_action_wet",
		"move_look",
		"move_push",
		"move_aim",
		"move_aim_lock",
		"move_aim_up",
		"move_digest",
		"move_instant",
		"move_tongue_axis",
		"move_swallow_queue",
		"move_dive",
		"move_water_jump",
		"move_snow",
		"move_jump_carry",
		"move_flow",
		"move_flutter_flow"
	]:
		if state[name] not in [0, 1]:
			return false
	for limit: Array in [
		["move_action", NORMAL, SWALLOW],
		["move_action_tick", 0, 35],
		["move_posture_tick", 0, 9],
		["move_turn_ticks", 0, 30],
		["move_pound_delay", 0, 6],
		["move_aim_angle", -90000, 45000],
		["move_eggs", 0, 6],
		["move_ammo", 0, COLD],
		["move_ammo_count", 0, 60],
		["move_digest_ticks", 0, 18],
		["move_tongue_phase", TONGUE_NONE, TONGUE_FAILED],
		["move_tongue_block_tick", 0, 12],
		["move_tongue_hold", 0, 128 * S],
		["move_tongue_length", 0, 128 * S],
		["move_gravity_tick", 0, 24],
		["move_water_transition", 0, 9],
		["move_spread", 0, 14000]
	]:
		if state[limit[0]] < limit[1] or state[limit[0]] > limit[2]:
			return false
	for name: String in ["move_held_id", "move_held_speed", "move_impact"]:
		if state[name] < 0:
			return false
	if state.move_turn not in [-1, 0, 1] or state.move_aim_dir not in [-1, 1]:
		return false
	if state.move_aim and (not state.move_eggs or state.swimming or state.move_duck):
		return false
	if (
		state.move_digest and not state.move_held_id
		or state.move_instant and not state.move_held_id
	):
		return false
	if state.move_ammo_count and not state.move_ammo:
		return false
	if (state.move_action == TONGUE) != (state.move_tongue_phase != TONGUE_NONE):
		return false
	var durations := {
		POUND_START: 24, SPIT: 10, HEAD_BUMP: 10, LAND: 4, TOSS: 13, LAY: 25, SWALLOW: 35
	}
	if durations.has(state.move_action) and state.move_action_tick >= durations[state.move_action]:
		return false
	return (
		state.get("previous_input", 0) is int
		and state.get("movement", 0) is int
		and (state.get("previous_input", 0) & ~INPUT_MASK) == 0
		and state.get("movement", 0) >= 0
		and state.get("movement", 0) <= 6
		and Requests.valid_state(state)
	)
