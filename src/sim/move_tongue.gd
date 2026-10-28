extends RefCounted
## Read-only mouth and tongue geometry in fixed-point units.
const S := preload("res://src/sim/units.gd").SCALE


static func mouth(state: Dictionary, spitting: bool) -> Array:
	var x := 24 * S
	var y := -24 * S
	if state.move_tongue_axis:
		x = (4 if state.move_action_wet else 14) * S
		y = -38 * S
		if spitting:
			x = 13 * S if state.move_action_wet else 14 * S
			y = -41 * S - S / 15 if state.move_action_wet else -38 * S
	return [state.x + state.facing * x, state.y + y]


static func probe(state: Dictionary, spitting: bool) -> Array:
	var x := 32 * S
	var y := -24 * S
	if state.move_tongue_axis:
		x = (10 if state.move_action_wet else 20) * S
		y = -52 * S
		if state.move_action_wet and spitting:
			x = 18 * S + 2 * S / 5
			y = -56 * S - 14 * S / 15
	x = state.x + state.facing * x
	y += state.y
	return [x - 12 * S, y - 12 * S, x + 12 * S, y + 12 * S]


static func ammo_mouth(state: Dictionary) -> Array:
	var x := (34 if state.swimming else 30) * S
	var y := (-24 if state.swimming else -28) * S
	if state.move_tongue_axis:
		x = (16 if state.swimming else 18) * S
		y = (-60 if state.swimming else -54) * S
	return [state.x + state.facing * x, state.y + y]


static func sensor_box(state: Dictionary, length: int) -> Array:
	var origin := mouth(state, false)
	if state.move_tongue_axis:
		return [
			origin[0] - 7 * S,
			origin[1] - length - 4 * S,
			origin[0] + 7 * S,
			origin[1] - length + 44 * S
		]
	var tip: int = origin[0] + state.facing * length
	return [
		tip - (40 if state.facing > 0 else 8) * S,
		origin[1] - 7 * S,
		tip + (8 if state.facing > 0 else 40) * S,
		origin[1] + 7 * S
	]


static func reach_box(state: Dictionary, length: int) -> Array:
	var origin := mouth(state, false)
	var box := sensor_box(state, length)
	if state.move_tongue_axis:
		box[3] = maxi(box[3], origin[1])
	else:
		box[0] = mini(box[0], origin[0])
		box[2] = maxi(box[2], origin[0])
	return box
