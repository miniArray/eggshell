extends RefCounted
## Flutter lift: start, damping, end and the gravity recovery after it. A leaf of Moves:
## it reads and writes player fields only and imports no world or collision code.
const InputBits = preload("res://src/sim/move_input.gd")
const Sound = preload("res://src/sim/sound_events.gd")
const S := preload("res://src/sim/units.gd").SCALE
## The end timer (0.66 s, 0.82 s boosted) is checked after the step's damping, so the
## lift damps on one more step than its whole-step length.
const TICKS := 41
const BOOSTED_TICKS := 51
## The delay after a cancel (0.266 s) still counts as running on the step it expires,
## so the next flutter can start 17 steps after the cancel.
const COOLDOWN := 17
## A flutter that lands lifts the body this far before the next move.
const LANDING_LIFT := 2 * S
## Gravity after the lift runs out: one step of full gravity, then the recovery from 1024
## to 2048 px/s^2 over 0.4 s, sampled at 1/24 steps of its sine ease-out curve.
const GRAVITY_RECOVERY := [
	2048,
	1080,
	1149,
	1219,
	1287,
	1353,
	1417,
	1478,
	1537,
	1594,
	1647,
	1698,
	1746,
	1791,
	1833,
	1871,
	1906,
	1938,
	1966,
	1990,
	2010,
	2026,
	2038,
	2046
]
const NONE := 0
const STARTED := 1
const LANDED := 2


static func cancel(state: Dictionary) -> void:
	if state.flutter_remaining:
		state.flutter_cooldown = COOLDOWN
	state.flutter_remaining = 0
	state.move_flutter_flow = 0


## One flutter step: STARTED when a lift starts, LANDED when a lift that landed ends
## here (the caller lifts the body before the move), NONE otherwise.
static func step(state: Dictionary, input: int) -> int:
	if state.flutter_remaining and state.on_floor:
		state.vx = clampi(state.vx, -256 * 60, 256 * 60)
		cancel(state)
		return LANDED
	var result := NONE
	if (
		not state.on_floor
		and not state.flutter_remaining
		and state.flutter_ready
		and state.flutter_cooldown == 0
		and input & InputBits.JUMP
		and state.vy > 192 * 60
	):
		state.flutter_remaining = BOOSTED_TICKS if state.boosted_flutter else TICKS
		state.flutter_ready = 0
		Sound.player(state)
		state.vy = mini(state.vy, 392 * 60)
		state.move_gravity_tick = 0
		result = STARTED
	if not state.flutter_remaining:
		return result
	if state.move_flow != state.move_flutter_flow:
		state.flutter_remaining = maxi(
			1, state.flutter_remaining + (21 if state.move_flow else -21)
		)
		state.move_flutter_flow = state.move_flow
	# Fixed rational coefficients for the two supported contact states at 60 Hz.
	var coefficient := 50569 if state.move_flutter_flow else 37649
	state.vy += ((-424 if state.boosted_flutter else -264) * 60 - state.vy) * coefficient / 1000000
	state.vx = clampi(state.vx, -256 * 60, 256 * 60)
	state.flutter_remaining -= 1
	if state.flutter_remaining == 0:
		state.flutter_cooldown = COOLDOWN
		state.move_gravity_tick = 1
		state.move_flutter_flow = 0
	return result


## Gravity of this step's recovery, advancing it; the caller checks move_gravity_tick.
static func recovery_gravity(state: Dictionary) -> int:
	var tick: int = state.move_gravity_tick - 1
	state.move_gravity_tick = tick + 2 if tick < 23 else 0
	return GRAVITY_RECOVERY[tick]
