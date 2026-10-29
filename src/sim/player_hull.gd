extends RefCounted
## A cheap early-out for contact tests: every box `Moves.player_box` returns lies inside
## HULL around the player's position, so an area the hull misses no player box touches.
## tests/moves.gd checks the hull against the player boxes.

const S := preload("res://src/sim/units.gd").SCALE
const HULL := [-14 * S, -60 * S, 12 * S, 14 * S]


## True when no player box can overlap the area [left, top, right, bottom] (touching
## edges count as overlapping).
static func misses(state: Dictionary, left: int, top: int, right: int, bottom: int) -> bool:
	var x: int = state.x
	var y: int = state.y
	return x + HULL[2] < left or x + HULL[0] > right or y + HULL[3] < top or y + HULL[1] > bottom
