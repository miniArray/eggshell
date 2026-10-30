extends RefCounted
## One frame of the original's catch freeze (time scale 0). Input events still run:
## the release cut (Yoshi 52) and Platform's jump from a floor. Every time-scaled rule
## (motion, gravity, acceleration, timers) adds zero, so the body and world stay still.

const Moves = preload("res://src/sim/moves.gd")
const Collision = preload("res://src/sim/collision.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const S := preload("res://src/sim/units.gd").SCALE


static func advance(state: Dictionary, world: Dictionary, pressed: int, released: int) -> void:
	Moves.initialize(state)
	if state.hurt or state.swimming:
		return
	if released & InputBits.JUMP and state.vy < 0:
		state.vy /= 4
	if (
		pressed & InputBits.JUMP
		and state.vy >= 0
		and state.move_action not in [Moves.POUND_START, Moves.POUND_FALL, Moves.POUND_LAND]
		and Collision.floor_at(state, world, Moves.player_box(state)) != 0
		and not Collision.overlaps(state, world, Moves.NORMAL_BOX, 0, -S)
	):
		Moves.jump(state)
