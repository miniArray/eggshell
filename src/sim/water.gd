extends RefCounted
## Buoyancy and posture are integer state. Bobbing uses a fixed quadratic path.
const World = preload("res://src/sim/world.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const S := preload("res://src/sim/units.gd").SCALE


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
			state.water_wait = 15
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
	return 4 * S * (60 * tick - tick * tick) / 900


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
