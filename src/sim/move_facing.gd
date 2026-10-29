extends RefCounted
## Which way the player faces, decided before its actions from the held directions.
## A leaf of Moves: it reads and writes player fields only.
const InputBits = preload("res://src/sim/move_input.gd")


## Holding one direction faces it at once in the air or on snow. On other floors the
## held direction is faced once the body already moves that way. Aiming, swimming,
## crouching and the caller's locked poses (pound, lay, tongue, spit, emission) keep it.
static func update(state: Dictionary, input: int, locked: bool) -> void:
	if locked or state.move_aim or state.swimming or state.move_duck:
		return
	var right := bool(input & InputBits.RIGHT)
	var left := bool(input & InputBits.LEFT)
	var free: bool = not state.on_floor or state.move_snow
	if right and ((free and not left) or (state.on_floor and state.vx > 0)):
		state.facing = 1
	if left and ((free and not right) or (state.on_floor and state.vx < 0)):
		state.facing = -1
