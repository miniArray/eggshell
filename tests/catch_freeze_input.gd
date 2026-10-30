extends SceneTree
## Invented floor only. The catch freeze stops time; input events still change velocity.
const Courses = preload("res://tests/moves.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const S := 3600
const RIGHT := InputBits.RIGHT
const JUMP := InputBits.JUMP
var checks := 0
var failures := 0


func _initialize() -> void:
	release_during_catch()
	jump_during_catch()
	held_jump_does_not_repeat()
	release_then_resume()
	frozen_steps_restore()
	print("CATCH_FREEZE_INPUT_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func caught(on_floor: bool, input: int) -> Dictionary:
	var world := Courses.floor_world()
	var state := Courses.actor(world)
	for tick in 30:
		Sim.advance(state, 0, world)
	check(state.on_floor == 1, "The invented body stands on the floor")
	if not on_floor:
		state.y -= 64 * S
		state.vy = -366 * 60
		state.on_floor = 0
	state.vx = 145 * 60
	state.previous_input = input
	state.separated = 1
	state.companion_mode = Life.RETURNING
	state.life_phase = Life.REJOIN
	state.life_ticks = 30
	return {"state": state, "world": world}


func release_during_catch() -> void:
	var unit := caught(false, RIGHT | JUMP)
	var state: Dictionary = unit.state
	var x: int = state.x
	var y: int = state.y
	Sim.advance(state, RIGHT, unit.world)
	check(state.vy == -366 * 60 / 4, "Releasing jump in the freeze cuts rising velocity")
	check(state.x == x and state.y == y, "The frozen body does not move")
	check(state.vx == 145 * 60, "Frozen time adds no horizontal acceleration")
	check(state.life_phase == Life.REJOIN, "The freeze continues")


func jump_during_catch() -> void:
	var unit := caught(true, RIGHT)
	var state: Dictionary = unit.state
	var y: int = state.y
	Sim.advance(state, RIGHT | JUMP, unit.world)
	check(
		state.vy == -Moves.JUMP_SPEED, "A jump press on the floor in the freeze sets jump velocity"
	)
	check(state.y == y, "The frozen jump does not move the body")
	Sim.advance(state, RIGHT | JUMP, unit.world)
	check(state.vy == -Moves.JUMP_SPEED, "Frozen time adds no gravity to the jump")
	Sim.advance(state, RIGHT, unit.world)
	check(state.vy == -Moves.JUMP_SPEED / 4, "A later release in the same freeze cuts the jump")


func held_jump_does_not_repeat() -> void:
	var unit := caught(true, RIGHT | JUMP)
	var state: Dictionary = unit.state
	Sim.advance(state, RIGHT | JUMP, unit.world)
	check(state.vy == 0, "A jump already held when the freeze began does not start a new jump")


func release_then_resume() -> void:
	var unit := caught(false, RIGHT | JUMP)
	var state: Dictionary = unit.state
	# Ticks 2 -> 1 is the last frozen step; 1 -> 0 is the step that moves again.
	state.life_ticks = 2
	Sim.advance(state, RIGHT, unit.world)
	check(state.vy == -366 * 60 / 4, "A release on the last frozen step still cuts velocity")
	var y: int = state.y
	Sim.advance(state, RIGHT, unit.world)
	check(state.life_phase == Life.PLAY, "Play resumes after the freeze")
	check(state.y < y and state.y > y - 2 * S, "The body resumes from the cut velocity")


func frozen_steps_restore() -> void:
	var unit := caught(false, RIGHT | JUMP)
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "A frozen state saves")
	var other := caught(false, RIGHT | JUMP)
	var decoded := Snapshot.decode(bytes, unit.state.identity, other.world)
	check(decoded.ok, "A frozen state restores")
	if not decoded.ok:
		return
	for input in [RIGHT, RIGHT | JUMP, RIGHT, RIGHT | JUMP]:
		Sim.advance(unit.state, input, unit.world)
		Sim.advance(decoded.state, input, other.world)
	check(Snapshot.encode(unit.state) == Snapshot.encode(decoded.state), "Frozen input replays")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
