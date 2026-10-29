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
