extends RefCounted
## Buoyancy and posture are integer state. Bobbing follows a fixed per-step table.
const World = preload("res://src/sim/world.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const S := preload("res://src/sim/units.gd").SCALE
## Floating bob: 4 px down over 0.5 s and back, along the source's sine ease-out curve,
## sampled per step (fixed units of 1/3600 px).
const BOB := [
	0,
	604,
	1372,
	2154,
	2931,
	3695,
	4441,
	5168,
	5874,
	6558,
	7219,
	7856,
	8469,
	9057,
	9619,
	10154,
	10662,
	11142,
	11594,
	12016,
	12407,
	12767,
	13094,
	13388,
	13647,
	13871,
	14057,
	14204,
	14312,
	14378,
	14400
]


static func prepare(
	state: Dictionary, input: int, world: Dictionary, pressed := 0, posture_allowed := true
) -> Dictionary:
	if (
		not state.swimming
		and (
			World.water_at(world, state.x, state.y - 66 * S)
			or state.on_floor and World.water_at(world, state.x, state.y - 42 * S)
		)
	):
		state.swimming = 1
		state.hurt_deceleration = 128
		state.water_phase = 0
		state.water_wait = 0
		state.water_deep = 0
		state.move_water_jump = 0
	if not state.swimming:
		return {"bob": 0, "jump": false}
	if state.move_water_jump and state.vy >= 0:
		state.move_water_jump = 0
	var deep := World.water_at(world, state.x, state.y - 34 * S)
	if deep:
		if not state.water_deep:
			state.vy = 0
			state.water_wait = 16
		if state.water_wait:
			state.water_wait -= 1
		else:
			state.vy -= 384
	else:
		if not World.water_at(world, state.x, state.y - 28 * S):
			state.vy += 256
		if state.vy < 0 and not state.move_water_jump:
			state.vy = 0
	state.water_deep = int(deep)
	if posture_allowed:
		var dive := int(bool(input & InputBits.DOWN) and not state.move_water_jump)
		if dive != state.move_dive:
			state.move_dive = dive
			state.move_water_transition = 9
		else:
			state.move_water_transition = maxi(0, state.move_water_transition - 1)
		if dive and state.vx and state.move_water_transition <= 3:
			state.move_water_transition = 0
	var phase: int = state.water_phase
	state.water_phase = (phase + 1) % 60
	var bob := bob_position(phase + 1) - bob_position(phase)
	var jump: bool = (
		bool(pressed & InputBits.JUMP)
		and state.vy < 96 * 60
		and not World.water_at(world, state.x, state.y - 50 * S)
	)
	if jump:
		state.move_water_jump = 1
		state.move_dive = 0
		return {"bob": 0, "jump": true}
	return {"bob": bob, "jump": false}


## Whether the body box overlaps water anywhere (the source's liquid contact).
static func body_overlaps(state: Dictionary, world: Dictionary, bounds: Array) -> bool:
	return World.water_overlaps(
		world, state.x + bounds[0], state.y + bounds[1], state.x + bounds[2], state.y + bounds[3]
	)


static func bob_position(phase: int) -> int:
	var tick := phase if phase <= 30 else 60 - phase
	return BOB[tick]


static func finish(state: Dictionary, world: Dictionary, bounds: Array) -> void:
	if (
		state.swimming
		and not World.water_overlaps(
			world,
			state.x + bounds[0],
			state.y + bounds[1],
			state.x + bounds[2],
			state.y + bounds[3]
		)
	):
		state.swimming = 0
		state.hurt_deceleration = 1296
		state.water_wait = 0
		state.water_phase = 0
		state.water_deep = 0
		state.move_dive = 0
		state.move_water_transition = 0
		state.move_water_jump = 0
