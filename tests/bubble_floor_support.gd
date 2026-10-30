extends SceneTree
## Invented descending terrain only. No original levels, assets or recordings.
const Courses = preload("res://tests/moves.gd")
const Bubble = preload("res://src/sim/companion_bubble.gd")
const Collision = preload("res://src/sim/collision.gd")
const Life = preload("res://src/sim/life.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	upward_bubble_follows_descending_ramp()
	unsupported_bubble_keeps_rising()
	saved_support_replays_through_simulation()
	print("BUBBLE_FLOOR_SUPPORT_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func fixture(ramp: bool = true) -> Dictionary:
	var world := Courses.empty_world()
	var cells := []
	for column in range(10, 26):
		cells.append([column, column])
	if ramp:
		world.layers = [Courses.layer("invented_ramp", true, false, cells, [0, 0, 1, 1, 0, 1])]
	var state := Courses.actor(world)
	state.separated = 1
	state.companion_mode = Life.BUBBLE
	state.companion_age = 3
	state.companion_vx = 1536
	state.companion_vy = -576
	state.companion_direction = 1
	state.recovery_x = 528 * S
	# The lower-left octagon vertex touches this slope when origin Y = X - 14 px.
	# A 3/4 px gap is inside the floor probe, but the next rightward move leaves it.
	state.recovery_y = (528 - 14) * S - 3 * S / 4
	return {"world": world, "state": state}


func upward_bubble_follows_descending_ramp() -> void:
	var unit := fixture()
	var state: Dictionary = unit.state
	var world: Dictionary = unit.world
	var initial := {"x": state.recovery_x, "y": state.recovery_y}
	check(not Collision.overlaps(initial, world, Bubble.body()), "Bubble starts clear of the ramp")
	check(
		Collision.floor_at(initial, world, Bubble.body()) == -1,
		"Upward Bubble is within the floor probe"
	)
	var unsupported := initial.duplicate()
	unsupported.x += 1792
	check(
		Collision.floor_at(unsupported, world, Bubble.body()) == 0,
		"Rightward motion leaves the old floor probe"
	)
	var y: int = state.recovery_y
	Bubble.advance(state, world)
	check(state.companion_vy == -768, "Bubble keeps its upward sway velocity")
	check(state.companion_age == 4, "Floor support does not change the sway timer")
	check(state.companion_vx == 2048, "Floor support does not change horizontal acceleration")
	check(
		state.recovery_x == initial.x + 1792,
		"Horizontal displacement keeps its existing integration"
	)
	check(
		state.recovery_y > y,
		"Actual Bubble.advance follows the descending ramp despite upward velocity"
	)
	check(
		(
			Collision.floor_at({"x": state.recovery_x, "y": state.recovery_y}, world, Bubble.body())
			== -1
		),
		"Descending-ramp movement retains floor support"
	)


func unsupported_bubble_keeps_rising() -> void:
	var unit := fixture(false)
	var x: int = unit.state.recovery_x
	var y: int = unit.state.recovery_y
	Bubble.advance(unit.state, unit.world)
	check(unit.state.recovery_x == x + 1792, "An unsupported Bubble keeps the same horizontal move")
	check(
		unit.state.recovery_y == y - 768,
		"An unsupported Bubble continues upward without a ramp snap"
	)


func saved_support_replays_through_simulation() -> void:
	var unit := fixture()
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "The upward Bubble saves: " + Snapshot.refusal(unit.state))
	var restored_unit := fixture()
	var decoded := Snapshot.decode(bytes, unit.state.identity, restored_unit.world)
	check(decoded.ok, "The saved Bubble restores before ramp following")
	if not decoded.ok:
		return
	var y: int = unit.state.recovery_y
	Sim.advance(unit.state, 0, unit.world)
	Sim.advance(decoded.state, 0, restored_unit.world)
	check(unit.state.recovery_y > y, "The real Sim.advance path follows the descending ramp")
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(decoded.state),
		"Restore recomputes the same floor support; no unsaved support cache is needed"
	)
	for tick in 12:
		Sim.advance(unit.state, 0, unit.world)
		Sim.advance(decoded.state, 0, restored_unit.world)
		var future := Snapshot.encode(unit.state)
		check(not future.is_empty(), "The ramp-following future stays valid")
		check(future == Snapshot.encode(decoded.state), "The restored Bubble keeps the same future")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
