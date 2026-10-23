class_name Simulation
extends RefCounted
## Exactly one 60 Hz tick. No nodes, effects, clocks or engine physics.

const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const Springs = preload("res://src/sim/bounce_pad.gd")
const Enemies = preload("res://src/sim/enemies.gd")
const Damage = preload("res://src/sim/damage.gd")
const Water = preload("res://src/sim/water.gd")
const S := State.SCALE
const LEFT := 1
const RIGHT := 2
const JUMP := 4
const RUN := 8
const ACCELERATION := 512
const DECELERATION := 1296
const GRAVITY := 2048
const JUMP_VELOCITY := -776 * 60
const MAX_FALL := 704 * 60
const WALK_SPEED := 240 * 60
const RUN_SPEED := 400 * 60


static func advance(state: Dictionary, input: int, world: Dictionary) -> void:
	if state.goal_reached:
		return
	var pressed: int = input & ~state.previous_input
	var released: int = state.previous_input & ~input
	state.previous_input = input
	state.frame += 1
	if Damage.prepare(state):
		Damage.respawn(state, world)
	Enemies.advance(state, world, pressed)
	if state.captured_by:
		state.camera_x = state.x
		state.camera_y = state.y - 28 * S
		return
	var action := 0 if state.hurt else input
	if state.hurt:
		pressed = 0
		released = 0
	Springs.advance(state, world)
	state.jump_buffer = 5 if pressed & JUMP else maxi(0, state.jump_buffer - 1)
	state.flutter_cooldown = maxi(0, state.flutter_cooldown - 1)
	if released & JUMP:
		if not state.flutter_remaining and not state.flutter_ready:
			state.boosted_flutter = 0
		state.flutter_ready = 1
		if state.flutter_remaining:
			state.flutter_remaining = 0
			state.flutter_cooldown = 16
	var bob := Water.prepare(state, action, world)
	var direction := int(bool(action & RIGHT)) - int(bool(action & LEFT))
	var speed := RUN_SPEED if input & RUN else WALK_SPEED
	if state.swimming:
		speed = 200 * 60
		state.vx = clampi(state.vx, -speed, speed)
	if direction:
		state.facing = direction
		state.vx = approach(state.vx, direction * speed, ACCELERATION)
	else:
		state.vx = approach(state.vx, 0, state.hurt_deceleration if state.hurt else DECELERATION)
	if not state.swimming and state.on_floor and state.jump_buffer:
		state.vy = JUMP_VELOCITY
		state.on_floor = 0
		state.jump_buffer = 0
		state.flutter_ready = 0
	if not state.swimming and released & JUMP and state.vy < 0:
		state.vy = int(state.vy / 4)
	if (
		not state.swimming
		and not state.on_floor
		and not state.flutter_remaining
		and state.flutter_ready
		and state.flutter_cooldown == 0
		and action & JUMP
		and state.vy > 192 * 60
	):
		state.flutter_remaining = 50 if state.boosted_flutter else 40
		state.flutter_ready = 0
		state.vy = mini(state.vy, 392 * 60)
	if state.swimming:
		state.flutter_remaining = 0
	elif state.flutter_remaining:
		state.vy += int(
			((-424 if state.boosted_flutter else -264) * 60 - state.vy) * 37649 / 1000000
		)
		state.vx = clampi(state.vx, -256 * 60, 256 * 60)
		state.flutter_remaining -= 1
		if state.flutter_remaining == 0:
			state.flutter_cooldown = 16
	else:
		state.vy = mini(state.vy + GRAVITY, MAX_FALL)
	var moved := move_axis(state, world, state.vx, true)
	if moved != state.vx:
		state.vx = 0
	var vertical_distance: int = state.vy + bob
	var falling: bool = vertical_distance >= 0
	var before_y: int = state.y
	moved = move_axis(state, world, vertical_distance, false)
	state.on_floor = int(falling and moved != vertical_distance)
	state.support_bridge = 0
	for index in world.bridges.size():
		var bridge: Dictionary = world.bridges[index]
		if (
			falling
			and before_y <= bridge.top
			and state.y >= bridge.top
			and state.x + 12 * S > bridge.left
			and state.x - 12 * S < bridge.right
		):
			state.y = bridge.top
			state.on_floor = 1
			state.support_bridge = index + 1
			moved = state.y - before_y
	if state.on_floor:
		state.boosted_flutter = 0
		state.flutter_remaining = 0
		state.flutter_cooldown = 0
	if state.on_floor or moved != vertical_distance:
		state.vy = 0
	state.x = clampi(state.x, 12 * S, world.width - 12 * S)
	if state.y > world.height + 96 * S:
		Damage.respawn(state, world)
	Water.finish(state, world)
	Springs.contact(state, action, world)
	Enemies.contact(state, action, world)
	Damage.recover(state)
	# Store the desired focus only. View-size-dependent clamping belongs to the view.
	state.camera_x = state.x
	state.camera_y = state.y - 28 * S
	state.movement = 0 if state.vx == 0 else (2 if input & RUN else 1)
	if not state.on_floor:
		state.movement = 3 if state.vy < 0 else 4
	if state.flutter_remaining:
		state.movement = 6
	for goal: Array in world.goals:
		if (
			state.x + 12 * S > goal[0] - 8 * S
			and state.x - 12 * S < goal[0] + 8 * S
			and state.y > goal[1] - 8 * S
			and state.y - 56 * S < goal[1] + 8 * S
		):
			state.goal_reached = 1
			state.movement = 5


static func approach(value: int, target: int, amount: int) -> int:
	return mini(value + amount, target) if value < target else maxi(value - amount, target)


static func move_axis(state: Dictionary, world: Dictionary, distance: int, horizontal: bool) -> int:
	if distance == 0:
		return 0
	var dx := distance if horizontal else 0
	var dy := 0 if horizontal else distance
	var moved := distance
	if World.overlaps(world, state.x + dx, state.y + dy):
		var low := 0
		var high := absi(distance)
		var signum := 1 if distance > 0 else -1
		while low < high:
			var middle := (low + high + 1) / 2
			dx = middle * signum if horizontal else 0
			dy = 0 if horizontal else middle * signum
			if World.overlaps(world, state.x + dx, state.y + dy):
				high = middle - 1
			else:
				low = middle
		moved = low * signum
	if horizontal:
		state.x += moved
	else:
		state.y += moved
	return moved
