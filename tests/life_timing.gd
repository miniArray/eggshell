extends SceneTree
## Control timing around hurts, deaths and the level start, through the real step.
## Synthetic courses only: an open sky and a flat floor.

const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Life = preload("res://src/sim/life.gd")
const Damage = preload("res://src/sim/damage.gd")
const Bits = preload("res://src/sim/move_input.gd")
const Courses = preload("res://tests/moves.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	knocked_lock_checks()
	look_around_checks()
	spin_lock_checks()
	validation_checks()
	print("LIFE_TIMING_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Number of steps after `state` until input RIGHT first changes the result,
## compared with the same state stepped without input. -1 when it never does.
func first_input_step(state: Dictionary, world: Dictionary, limit: int) -> int:
	var held := state.duplicate(true)
	var idle := state.duplicate(true)
	for count in range(1, limit + 1):
		Sim.advance(held, Bits.RIGHT, world)
		Sim.advance(idle, 0, world)
		if held.vx != idle.vx or held.x != idle.x or held.facing != idle.facing:
			return count
	return -1


func first_floor_step(state: Dictionary, world: Dictionary, limit: int) -> int:
	var idle := state.duplicate(true)
	for count in range(1, limit + 1):
		Sim.advance(idle, 0, world)
		if idle.on_floor:
			return count
	return -1


func hurt_player(world: Dictionary, height_above_floor: int) -> Dictionary:
	var state := Courses.actor(world)
	state.y = world.spawn_y - height_above_floor
	for count in 2:
		Sim.advance(state, 0, world)
	state.vx = 0
	state.vy = 0
	state.on_floor = 0
	# The hit lands in this step's contact phase, after the player moved.
	Damage.hurt(state, state.x + S)
	return state


func knocked_lock_checks() -> void:
	var world := Courses.empty_world()
	var state := hurt_player(world, 0)
	check(state.hurt_phase == Life.HURT_KNOCKED, "a first dry hit starts the knock-back pose")
	check(
		first_input_step(state, world, 80) == Life.KNOCKED_LOCK,
		"airborne knock-back ignores input for 37 steps and accepts it on the 38th"
	)
	var probe := state.duplicate(true)
	for count in Life.KNOCKED_LOCK - 2:
		Sim.advance(probe, 0, world)
	check(probe.hurt_phase == Life.HURT_KNOCKED, "the pose lasts while two lock steps remain")
	Sim.advance(probe, 0, world)
	check(
		probe.hurt_phase == Life.HURT_NONE and probe.hurt == 1,
		"the pose ends one step before the input lock"
	)


func look_around_checks() -> void:
	var world := Courses.floor_world()
	var state := hurt_player(world, 4 * S)
	var landing := first_floor_step(state, world, 60)
	check(landing > 0 and landing < 36, "the synthetic knock-back lands inside the pose")
	check(
		first_input_step(state, world, 120) == landing + Life.LOOK_AROUND_LOCK,
		"landing in the knock-back pose locks input for the 42-step look-around"
	)
	var probe := state.duplicate(true)
	for count in landing:
		Sim.advance(probe, 0, world)
	check(
		probe.hurt_phase == Life.HURT_LOOK_AROUND and probe.hurt == Life.LOOK_AROUND_LOCK,
		"the landing step starts the look-around"
	)
	check(Life.valid_state(probe), "the look-around is valid saved state")
	# A pose that already ended by its timer does not look around on landing.
	var late := state.duplicate(true)
	late.hurt = 2
	Sim.advance(late, 0, world)
	check(late.hurt_phase == Life.HURT_NONE, "an expired pose cannot start the look-around")
	for count in 40:
		Sim.advance(late, 0, world)
	check(late.hurt == 0 and late.on_floor == 1, "landing after the pose keeps control")


func spin_lock_checks() -> void:
	var world := Courses.empty_world()
	var state := hurt_player(world, 0)
	state.invulnerable = 0
	state.hurt = 0
	state.hurt_phase = Life.HURT_NONE
	Damage.hurt(state, state.x + S)
	check(state.hurt_phase == Life.HURT_NONE, "a hit while separated spins instead")
	check(
		first_input_step(state, world, 100) == Life.SPIN_LOCK,
		"the spin ignores input for 62 steps and accepts it on the 63rd"
	)
	var floor_world := Courses.floor_world()
	var spun := hurt_player(floor_world, 4 * S)
	spun.invulnerable = 0
	spun.hurt = 0
	spun.hurt_phase = Life.HURT_NONE
	Damage.hurt(spun, spun.x + S)
	for count in 30:
		Sim.advance(spun, 0, floor_world)
	check(
		spun.on_floor == 1 and spun.hurt_phase == Life.HURT_NONE,
		"landing during a spin does not look around"
	)


func validation_checks() -> void:
	var world := Courses.empty_world()
	var state := Courses.actor(world)
	check(Life.valid_state(state), "a fresh player is valid")
	state.hurt_phase = Life.HURT_KNOCKED
	check(not Life.valid_state(state), "a pose without an input lock is invalid")
	state.hurt = Life.MAX_HURT
	check(Life.valid_state(state), "the longest lock is valid")
	state.hurt = Life.MAX_HURT + 1
	check(not Life.valid_state(state), "a lock beyond the longest is invalid")
	state.hurt = 5
	state.hurt_phase = 3
	check(not Life.valid_state(state), "an unknown hurt phase is invalid")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
