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
	restart_checks()
	dead_body_checks()
	level_start_checks()
	validation_checks()
	print("LIFE_TIMING_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Number of steps after `state` until input RIGHT first changes the result,
## compared with the same state stepped without input. -1 when it never does.
func first_input_step(state: Dictionary, world: Dictionary, limit: int, shared := 0) -> int:
	var held := state.duplicate(true)
	var idle := state.duplicate(true)
	for count in range(1, limit + 1):
		Sim.advance(held, Bits.RIGHT, world)
		Sim.advance(idle, Bits.RIGHT if count <= shared else 0, world)
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
		first_input_step(state, world, 80) == 1,
		"the direction held when the hit lands still pushes on the next step"
	)
	check(
		first_input_step(state, world, 80, 1) == Life.KNOCKED_LOCK,
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
		first_input_step(state, world, 120, 1) == landing + Life.LOOK_AROUND_LOCK,
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
		first_input_step(state, world, 100, 1) == Life.SPIN_LOCK,
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


func restart_checks() -> void:
	var world := Courses.floor_world()
	var state := Courses.actor(world)
	for count in 3:
		Sim.advance(state, 0, world)
	state.x += 200 * S
	# The death lands in this step's contact phase.
	Life.kill(state, Life.PIT)
	var ordinary := Life.DEATH_WAIT + Life.DEATH_FADE + Life.RESTART_STEPS
	check(ordinary == 304, "an ordinary death returns control 304 steps later")
	var steered := state.duplicate(true)
	Sim.advance(steered, Bits.RIGHT, world)
	var coasting := state.duplicate(true)
	Sim.advance(coasting, 0, world)
	check(steered.vx > coasting.vx, "input of the death frame still steers the body once")
	check(
		first_input_step(coasting, world, 400) + 1 == ordinary,
		"input works again on the 304th step after an ordinary death"
	)
	var probe := state.duplicate(true)
	for count in Life.DEATH_WAIT + Life.DEATH_FADE - 1:
		Sim.advance(probe, 0, world)
	check(probe.x != world.spawn_x, "the body stays until the fade completes")
	Sim.advance(probe, 0, world)
	check(
		probe.x == world.spawn_x and probe.life_phase == Life.FADE_IN,
		"the restart places the player on the step after the fade"
	)
	var quick := Courses.actor(world)
	Sim.advance(quick, 0, world)
	Life.quick_restart(quick)
	Sim.advance(quick, 0, world)
	check(
		first_input_step(quick, world, 100) + 1 == Life.QUICK_FADE + Life.RESTART_STEPS,
		"input works again on the 35th step after a quick death"
	)
	# A respawn point in the air: the body falls one step before input works.
	var air := Courses.empty_world()
	var falling := Courses.actor(air)
	Sim.advance(falling, 0, air)
	Life.quick_restart(falling)
	for count in Life.QUICK_FADE + Life.RESTART_STEPS - 1:
		Sim.advance(falling, Bits.RIGHT, air)
	check(
		falling.vy > 0 and falling.vx == 0 and falling.life_phase == Life.FADE_IN,
		"the last restart step moves the body without input"
	)


func dead_body_checks() -> void:
	var world := Courses.empty_world()
	var state := Courses.actor(world)
	for count in 60:
		Sim.advance(state, Bits.RIGHT, world)
	var x: int = state.x
	var y: int = state.y
	var vx: int = state.vx
	var camera := [state.camera_x, state.camera_y]
	Life.kill(state, Life.PIT)
	check(state.vx == vx and state.vy > 0, "a fall keeps the body's motion")
	Sim.advance(state, Bits.RIGHT, world)
	Sim.advance(state, Bits.RIGHT, world)
	check(state.y > y and state.x > x, "the body keeps falling after the death")
	check(state.vx == vx - Sim.DECELERATION, "a direction held at death leaves the air braking on")
	for count in 40:
		Sim.advance(state, Bits.RIGHT, world)
	check(
		state.vx == 0 and state.vy == Sim.MAX_FALL, "the body stops sliding and falls at full speed"
	)
	check(
		state.camera_x == camera[0] and state.camera_y == camera[1],
		"the camera does not follow the body"
	)
	var held := Courses.actor(world)
	for count in 40:
		Sim.advance(held, Bits.RIGHT, world)
	Life.kill(held, Life.HAZARD)
	var at := [held.x, held.y]
	for count in 20:
		Sim.advance(held, Bits.RIGHT, world)
	check(held.x == at[0] and held.y == at[1], "a hazard holds the body where it died")


func level_start_checks() -> void:
	var air := Courses.empty_world()
	var state := State.create(air)
	check(
		state.vy == 2 * Sim.GRAVITY and state.y == air.spawn_y + Sim.GRAVITY * 3 / 2,
		"a level starts after two body steps without input"
	)
	check(
		state.frame == 0 and state.play_ticks == 0 and state.attempt_ticks == 0,
		"the level-start steps are not counted"
	)
	check(state.camera_y == state.y - 28 * S, "the camera starts on the settled body")
	var ground := Courses.floor_world()
	var standing := State.create(ground)
	check(standing.on_floor == 1 and standing.vy == 0, "a start on the ground settles on it")
	check(
		first_input_step(standing, ground, 10) == 1,
		"input works on the first step after the level start"
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
