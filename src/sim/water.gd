extends RefCounted
## Water entry, buoyancy and surface jumping use fixed simulation steps.

const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const S := State.SCALE


static func prepare(state: Dictionary, input: int, world: Dictionary) -> int:
	if (
		not state.swimming
		and (
			World.water_at(world, state.x, state.y - 66 * S)
			or (state.on_floor and World.water_at(world, state.x, state.y - 42 * S))
		)
	):
		state.swimming = 1
		state.water_phase = 0
		state.water_wait = 0
		state.water_deep = 0
	if not state.swimming:
		return 0
	state.flutter_remaining = 0
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
		if state.vy < 0:
			state.vy = 0
	state.water_deep = int(deep)
	var phase: int = state.water_phase
	state.water_phase = (phase + 1) % 60
	var bob := 480 if phase < 30 else -480
	if input & 4 and state.vy < 96 * 60 and not World.water_at(world, state.x, state.y - 50 * S):
		state.vy = -776 * 60
		state.on_floor = 0
		state.jump_buffer = 0
		return 0
	return bob


static func finish(state: Dictionary, world: Dictionary) -> void:
	if (
		state.swimming
		and not World.water_overlaps(
			world, state.x - 12 * S, state.y - 56 * S, state.x + 12 * S, state.y
		)
	):
		state.swimming = 0
		state.water_wait = 0
		state.water_phase = 0
		state.water_deep = 0
