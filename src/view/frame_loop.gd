extends RefCounted
## The fixed-step and picture order shared by the game and its invariance test.
## A physics callback calls `tick`, then `step` when the simulation advances. A
## rendered frame draws `picture`. Sound observes exactly once per step.

const Sim = preload("res://src/sim/step.gd")
const Motion = preload("res://src/view/view_motion.gd")

## Blend pictures between steps. The game enables it on displays above 60 Hz.
var smooth := false
var _motion := Motion.new()
var _ticks := 0


## Count every physics callback, including those that do not advance the state.
func tick() -> void:
	_ticks += 1


## Advance one fixed step. `audio` may be null.
func step(state: Dictionary, input: int, world: Dictionary, audio: Node) -> void:
	if smooth:
		_motion.before_step(state, _ticks)
	Sim.advance(state, input, world)
	if audio != null:
		audio.observe(state)


## The state to draw. `fraction` is the elapsed part of the current step (0..1).
## Without smoothing, or while steps are paused, this is the state itself.
func picture(state: Dictionary, fraction: float, stepping: bool = true) -> Dictionary:
	if not smooth or not stepping:
		return state
	return _motion.shown(state, _ticks, fraction)


## Drop the recorded pose after the state is replaced, for example by a restore.
func restored() -> void:
	_motion.clear()


## True when the display refreshes faster than the fixed step.
static func wants_smooth(option: String, refresh_rate: float) -> bool:
	match option:
		"on", "true":
			return true
		"off", "false":
			return false
	return refresh_rate > 61.0
