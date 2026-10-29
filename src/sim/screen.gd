extends RefCounted
## The reference screen: a fixed 832×448 area that follows the saved camera follow point
## and stays inside the map. Every simulation "on screen" rule uses it: activation,
## despawn and respawn distances, goal coins, area clears and the egg count. It never
## depends on the real view; the view clamps the follow point for its own size.

const S := 3600
const HALF_WIDTH := 416 * S
const HALF_HEIGHT := 224 * S
## The follow point `camera_y` is the player's y minus 28 px.
const FOLLOW_LIFT := 28 * S
## The screen centre sits 64 px above the player while the player is between these
## distances from the top and the bottom of the map; outside them it stops at the edge.
const CENTRE_LIFT := 64 * S
const TOP_FOLLOW := 288 * S
const BOTTOM_FOLLOW := 160 * S


static func centre_x(state: Dictionary, world: Dictionary) -> int:
	var x: int = state.camera_x
	# The left limit applies below 416 px, then the right limit above width - 416 px.
	# On a map narrower than the screen both can apply, and then the later right limit
	# wins; a point at or left of width - 416 px keeps the left limit.
	if x > world.width - HALF_WIDTH:
		return world.width - HALF_WIDTH
	if x < HALF_WIDTH:
		return HALF_WIDTH
	return x


static func centre_y(state: Dictionary, world: Dictionary) -> int:
	var y: int = state.camera_y + FOLLOW_LIFT
	# The top limit applies above TOP_FOLLOW, then the bottom limit below height -
	# BOTTOM_FOLLOW. On a map shorter than the screen both can apply, and then the later
	# bottom limit wins; a point at or above height - BOTTOM_FOLLOW keeps the top limit.
	if y > world.height - BOTTOM_FOLLOW:
		return world.height - HALF_HEIGHT
	if y < TOP_FOLLOW:
		return HALF_HEIGHT
	return y - CENTRE_LIFT


## [left, top, right, bottom] of the screen.
static func area(state: Dictionary, world: Dictionary) -> Array:
	var x := centre_x(state, world)
	var y := centre_y(state, world)
	return [x - HALF_WIDTH, y - HALF_HEIGHT, x + HALF_WIDTH, y + HALF_HEIGHT]


## True when the box [left, top, right, bottom] overlaps the screen (open edges).
static func overlaps(state: Dictionary, world: Dictionary, box: Array) -> bool:
	var x := centre_x(state, world)
	var y := centre_y(state, world)
	return (
		box[2] > x - HALF_WIDTH
		and box[0] < x + HALF_WIDTH
		and box[3] > y - HALF_HEIGHT
		and box[1] < y + HALF_HEIGHT
	)
