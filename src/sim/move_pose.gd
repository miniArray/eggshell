extends RefCounted
## Pose facts the rules read without a graphics pack. A leaf of Moves.
const S := preload("res://src/sim/units.gd").SCALE


## How far below the map bottom the player's feet may fall before the pit takes it: the
## height of the pose the player shows. Airborne poses (plain action) use the original's
## frame heights (fall, jump, flutter, hurt; empty or full mouth); others keep 62 px.
static func pit_height(state: Dictionary, plain_action: bool) -> int:
	if state.get("on_floor", 0) or state.get("swimming", 0) or not plain_action:
		return 62 * S
	var full: bool = state.get("move_held_id", 0) != 0 or state.get("move_ammo_count", 0) != 0
	if state.get("hurt", 0):
		return 64 * S
	if state.get("flutter_remaining", 0):
		return (70 if full else 68) * S
	if state.get("vy", 0) < 0:
		return (72 if full else 66) * S
	return (64 if full else 66) * S


## Steady water poses have different attachment points from the standing reference.
## move_brake_vx is the movement velocity before contact damage changes vx.
static func companion_anchor(state: Dictionary, normal_action: bool) -> Array[int]:
	var dx := 10
	var dy := 24
	if (
		normal_action
		and state.get("swimming", 0)
		and not state.get("hurt", 0)
		and not state.get("move_water_transition", 0)
		and not state.get("move_water_jump", 0)
		and not state.get("move_dive", 0)
		and not state.get("move_aim", 0)
		and not state.get("move_duck", 0)
		and not state.get("move_look", 0)
	):
		var moving: bool = state.get("move_brake_vx", state.get("vx", 0)) != 0
		dx = 12 if moving else 10
		dy = 30 if moving else 32
	return [int(state.x) - int(state.facing) * dx * S, int(state.y) - dy * S]
