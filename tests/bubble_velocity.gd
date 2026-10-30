extends SceneTree
## Platform integrates acceleration before capping displacement and stored velocity.

const Courses = preload("res://tests/moves.gd")
const Bubble = preload("res://src/sim/companion_bubble.gd")
const S := 3600


func _initialize() -> void:
	var checks := 0
	var failures := 0
	for values: Array in [
		[-2560, -1, -2816, -2880],
		[2560, 1, 2816, 2880],
		[-2880, -1, -2880, -2880],
		[2880, 1, 2880, 2880],
		[0, -1, 0, -512]
	]:
		var world := Courses.empty_world()
		var state := Courses.actor(world)
		state.recovery_x = 512 * S
		state.recovery_y = 512 * S
		state.companion_vx = values[0]
		state.companion_direction = values[1]
		Bubble.advance(state, world)
		checks += 1
		if state.recovery_x != 512 * S + values[2]:
			print("FAIL: Displacement uses the uncapped accelerated endpoint, then its own cap")
			failures += 1
		checks += 1
		if state.companion_vx != values[3]:
			print("FAIL: Stored velocity is capped after movement")
			failures += 1
	print("BUBBLE_VELOCITY_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)
