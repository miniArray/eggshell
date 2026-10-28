class_name Simulation
extends RefCounted
## Exactly one 60 Hz tick. No nodes, effects, clocks or engine physics.

const State = preload("res://src/sim/play_state.gd")
const Collision = preload("res://src/sim/collision.gd")
const Registry = preload("res://src/sim/registry.gd")
const Maps = preload("res://src/sim/maps.gd")
const Life = preload("res://src/sim/life.gd")
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
	if not Maps.sync(state, world) or state.goal_reached:
		return
	state.frame += 1
	if Registry.modal_step(state, world, input):
		return
	if Life.before_step(state, world, Registry.spawn_map, Maps.change.bind(Registry.spawn_map)):
		Moves.reset(state)
	if Life.blocks_step(state):
		return
	var pressed: int = input & ~state.previous_input
	var released: int = state.previous_input & ~input
	state.previous_input = input
	Collision.begin_step(state, world, Registry)
	Registry.advance(state, world, pressed)
	if state.captured_by:
		state.camera_x = state.x
		state.camera_y = state.y - 28 * S
		return
	var action := 0 if state.hurt else input
	if state.hurt:
		pressed = 0
		released = 0
	Moves.advance(state, action, world, pressed, released)
	var phase: int = state.life_phase
	Registry.contact(state, action, world)
	if phase != Life.GOAL and state.life_phase == Life.GOAL:
		Registry.goal_convert(state, world, Life.goal_coin)
	var tongue := Moves.tongue_reach_box(state)
	if not tongue.is_empty():
		Life.catch_companion(state, tongue[0], tongue[1], tongue[2], tongue[3])
	Life.after_step(state, world)
	# Store the desired focus only. View-size-dependent clamping belongs to the view.
	state.camera_x = state.x
	state.camera_y = state.y - 28 * S
	if not Life.blocks_step(state):
		Moves.finish(state, action, world)


static func approach(value: int, target: int, amount: int) -> int:
	return mini(value + amount, target) if value < target else maxi(value - amount, target)


static func move_axis(state: Dictionary, world: Dictionary, distance: int, horizontal: bool) -> int:
	if not Collision.prepare(state, world, PLAYER_BOX):
		return 0
	var support := Collision.floor_at(state, world, PLAYER_BOX)
	if horizontal:
		return Collision.horizontal(state, world, PLAYER_BOX, distance, support, state.vy < 0)
	return Collision.vertical(state, world, PLAYER_BOX, distance, support)
