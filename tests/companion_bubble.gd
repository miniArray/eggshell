extends SceneTree
## Embedded drift reads the current body position after motion and after catch events.

const Courses = preload("res://tests/moves.gd")
const Sim = preload("res://src/sim/step.gd")
const Life = preload("res://src/sim/life.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	for axis in ["x", "y"]:
		for formation in [false, true]:
			current_body_position(axis, formation)
	catch_precedes_drift()
	ordered_comparisons()
	rescue_guards()
	frozen_and_bound_guards()
	bound_completion_order()
	print("COMPANION_BUBBLE_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func fixture() -> Dictionary:
	var world := Courses.empty_world()
	var filled := []
	for row in range(8, 25):
		for column in range(8, 25):
			filled.append([column, row])
	world.layers = [Courses.layer("terrain", true, false, filled)]
	var state := Courses.actor(world)
	state.separated = 1
	state.companion_mode = Life.BUBBLE
	state.companion_age = 61
	state.health = 10
	state.health_wait = 46
	state.recovery_x = 512 * S
	state.recovery_y = 512 * S
	return {"state": state, "world": world}


func current_body_position(axis: String, formation: bool) -> void:
	var unit := fixture()
	var state: Dictionary = unit.state
	state.x = (514 if axis == "x" else 128) * S
	state.y = (514 if axis == "y" else 128) * S
	state.vx = -400 * 60 if axis == "x" else 0
	state.vy = -384 * 60 if axis == "y" else 0
	if formation:
		state.companion_mode = Life.LAUNCH
		state.companion_age = Life.LAUNCH_STEPS - 1
		state.companion_from_x = 400 * S
		state.companion_dx = 112 * S
		state.companion_from_y = 512 * S
	Sim.advance(state, 0, unit.world)
	check(state[axis] < 512 * S, "The real player body crosses the embedded bubble this frame")
	check(
		state["recovery_" + axis] == 512 * S - 96 * 60,
		"Embedded drift follows the current player position, including the formation step"
	)
	var decoded := Snapshot.decode(Snapshot.encode(state), state.identity, unit.world)
	check(decoded.ok, "The post-motion drift state restores")
	if decoded.ok:
		var restored_world: Dictionary = unit.world.duplicate(true)
		for tick in 4:
			Sim.advance(state, 0, unit.world)
			Sim.advance(decoded.state, 0, restored_world)
		check(
			Snapshot.encode(state) == Snapshot.encode(decoded.state),
			"Restored drift replays exactly"
		)


func catch_precedes_drift() -> void:
	var unit := fixture()
	unit.state.x = unit.state.recovery_x
	unit.state.y = unit.state.recovery_y
	Life.after_step(unit.state, unit.world)
	check(unit.state.life_phase == Life.REJOIN, "An embedded companion can be caught first")
	check(
		unit.state.recovery_x == 512 * S and unit.state.recovery_y == 512 * S,
		"A successful catch suppresses the later drift event"
	)


func ordered_comparisons() -> void:
	for axis in ["x", "y"]:
		var unit := fixture()
		unit.state.x = 128 * S
		unit.state.y = 128 * S
		unit.state[axis] = 512 * S - S / 2
		Life.after_step(unit.state, unit.world)
		check(
			unit.state["recovery_" + axis] == 512 * S,
			"An overshooting first correction is reversed by the next independent comparison"
		)


func rescue_guards() -> void:
	for stolen in [false, true]:
		var unit := fixture()
		unit.state.x = 128 * S
		unit.state.y = 128 * S
		unit.state.rescue_active = 1
		unit.state.rescue_mask = 1 if stolen else 0
		Life.after_step(unit.state, unit.world)
		var expected := 512 * S - (0 if stolen else 96 * 60)
		check(
			unit.state.recovery_x == expected and unit.state.recovery_y == expected,
			"Approaching rescuers allow drift; an attached rescuer suppresses it"
		)


func frozen_and_bound_guards() -> void:
	for guard in ["frozen", "bound"]:
		var unit := fixture()
		unit.state.x = 128 * S
		unit.state.y = 128 * S
		if guard == "frozen":
			unit.state.life_phase = Life.REJOIN
		else:
			unit.state.bubble_bound_ticks = 2
			unit.state.bubble_collision_disabled = 1
		Life.after_step(unit.state, unit.world)
		check(
			unit.state.recovery_x == 512 * S and unit.state.recovery_y == 512 * S,
			"Frozen or bound bubbles do not run embedded drift"
		)


func bound_completion_order() -> void:
	var unit := fixture()
	unit.state.x = 128 * S
	unit.state.y = 128 * S
	unit.state.bubble_bound_ticks = 0
	unit.state.bubble_collision_disabled = 1
	Life.after_step(unit.state, unit.world)
	check(
		unit.state.recovery_x == 512 * S and unit.state.recovery_y == 512 * S,
		"The last bound-tween frame stays noncolliding through regular events"
	)
	check(
		unit.state.bubble_collision_disabled == 0, "Tick2 restores collisions after drift selection"
	)
	Life.after_step(unit.state, unit.world)
	check(unit.state.recovery_y == 512 * S - 96 * 60, "The following frame can drift again")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)
