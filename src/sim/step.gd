class_name Simulation
extends RefCounted
## Exactly one 60 Hz tick. No nodes, effects, clocks or engine physics.

const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/sim/collision.gd")
const Springs = preload("res://src/sim/bounce_pad.gd")
const Enemies = preload("res://src/sim/enemies.gd")
const Damage = preload("res://src/sim/damage.gd")
const Moves = preload("res://src/sim/moves.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const S := State.SCALE
const LEFT := InputBits.LEFT
const RIGHT := InputBits.RIGHT
const JUMP := InputBits.JUMP
const RUN := InputBits.USE  # Legacy mask alias; this bit now selects the use action.
const ACCELERATION := Moves.ACCELERATION
const DECELERATION := Moves.DECELERATION
const GRAVITY := Moves.GRAVITY
const JUMP_VELOCITY := -Moves.JUMP_SPEED
const MAX_FALL := Moves.MAX_FALL
const WALK_SPEED := Moves.MAX_SPEED
const RUN_SPEED := Moves.MAX_SPEED
const PLAYER_BOX := Moves.NORMAL_BOX


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
	if Moves.advance(state, action, world, pressed, released):
		Damage.respawn(state, world)
	Springs.contact(state, action, world)
	Enemies.contact(state, action, world)
	Damage.recover(state)
	# Store the desired focus only. View-size-dependent clamping belongs to the view.
	state.camera_x = state.x
	state.camera_y = state.y - 28 * S
	Moves.finish(state, action, world)
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
	if not Collision.prepare(state, world, PLAYER_BOX):
		return 0
	var support := Collision.floor_at(state, world, PLAYER_BOX)
	if horizontal:
		return Collision.horizontal(state, world, PLAYER_BOX, distance, support, state.vy < 0)
	return Collision.vertical(state, world, PLAYER_BOX, distance, support)
