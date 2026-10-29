extends SceneTree
## Control timing around hurts, deaths and the level start, through the real step.
## Synthetic courses only: an open sky and a flat floor.

const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Life = preload("res://src/sim/life.gd")
const Damage = preload("res://src/sim/damage.gd")
const Bits = preload("res://src/sim/move_input.gd")
const Moves = preload("res://src/sim/moves.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Courses = preload("res://tests/moves.gd")
const Fixtures = preload("res://tests/fixtures.gd")
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
	catch_input_checks()
	catch_freeze_checks()
	catch_water_checks()
	catch_buffered_jump_checks()
	catch_request_checks()
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


func caught_player(world: Dictionary) -> Dictionary:
	var state := Courses.actor(world)
	Life.separate(state, 0, true)
	check(
		Life.catch_companion(state, state.x - 32 * S, state.y - 80 * S, state.x + 32 * S, state.y),
		"the synthetic player catches the companion"
	)
	return state


func catch_input_checks() -> void:
	var air := Courses.empty_world()
	var released := caught_player(air)
	released.previous_input = Bits.RIGHT | Bits.JUMP
	released.vx = 358 * 60
	released.vy = -366 * 60
	released.move_action = Moves.HEAD_BUMP
	released.move_action_tick = 3
	released.flutter_cooldown = 7
	released.jump_buffer = 4
	var at := [released.x, released.y, released.vx, released.camera_x, released.camera_y]
	var clocks := [released.play_ticks, released.attempt_ticks, released.total_play_ticks]
	var entities: Array = released.entities.duplicate(true)
	Sim.advance(released, Bits.RIGHT, air)
	check(
		released.vy == -366 * 60 / 4,
		"releasing jump during the catch cuts rising speed immediately"
	)
	check(released.previous_input == Bits.RIGHT, "the catch consumes the release edge")
	for count in 10:
		Sim.advance(released, Bits.RIGHT, air)
	check(released.vy == -366 * 60 / 4, "a held release cuts speed once and adds no frozen gravity")
	check(
		[released.x, released.y, released.vx, released.camera_x, released.camera_y] == at,
		"catch input does not move the player or camera or accelerate the body"
	)
	check(
		(
			[released.play_ticks, released.attempt_ticks, released.total_play_ticks] == clocks
			and released.entities == entities
		),
		"catch input does not advance play clocks or world actors"
	)
	check(
		(
			released.move_action_tick == 3
			and released.flutter_cooldown == 7
			and released.jump_buffer == 4
		),
		"catch input does not advance action, flutter or buffered-jump timers"
	)
	var ground := Courses.floor_world()
	var jumped := caught_player(ground)
	at = [jumped.x, jumped.y]
	Sim.advance(jumped, Bits.RIGHT | Bits.JUMP, ground)
	check(
		jumped.vy == -Moves.JUMP_SPEED and not jumped.on_floor,
		"a new jump during the catch changes velocity without motion"
	)
	check(jumped.movement == 3, "a new jump during the catch selects the jump pose")
	check([jumped.x, jumped.y] == at, "a frozen jump does not move the grounded body")
	Sim.advance(jumped, Bits.RIGHT, ground)
	check(jumped.vy == -Moves.JUMP_SPEED / 4, "a frozen jump can be released before the catch ends")
	var decoded := Snapshot.decode(Snapshot.encode(jumped), ground.identity)
	check(decoded.ok, "a jump during the catch remains valid saved state")
	var restored: Dictionary = decoded.get("state", {}).duplicate(true)
	for count in Life.REJOIN_STEPS - 3:
		Sim.advance(jumped, Bits.RIGHT, ground)
		if decoded.ok:
			Sim.advance(restored, Bits.RIGHT, ground)
	check([jumped.x, jumped.y] == at, "the body stays frozen until the last catch step")
	Sim.advance(jumped, Bits.RIGHT | Bits.JUMP, ground)
	if decoded.ok:
		Sim.advance(restored, Bits.RIGHT | Bits.JUMP, ground)
	check(
		jumped.life_phase == Life.PLAY and jumped.y < at[1] and jumped.vy == -Moves.JUMP_SPEED / 4,
		"play resumes with the cut jump rather than a deferred full jump"
	)
	check(jumped == restored, "restoring inside the catch preserves input edges and future motion")


func catch_freeze_checks() -> void:
	var world := Fixtures.world()
	var state := caught_player(world)
	check(not state.entities.is_empty(), "the catch freeze includes real world actors")
	var entities: Array = state.entities.duplicate(true)
	state.move_action = Moves.TONGUE
	state.move_tongue_phase = Moves.TONGUE_OUT
	state.move_action_tick = 5
	state.move_digest_ticks = 4
	state.hurt = 2
	state.invulnerable = 19
	var clocks := [state.play_ticks, state.attempt_ticks, state.total_play_ticks]
	var at := [state.x, state.y]
	for count in 10:
		Sim.advance(state, Bits.RIGHT | Bits.JUMP, world)
	check(state.entities == entities, "catch input leaves every real world actor unchanged")
	check(
		[state.x, state.y] == at and state.hurt == 2 and state.invulnerable == 19,
		"a catch preserves the body and hurt/immunity timers"
	)
	check(
		(
			[state.play_ticks, state.attempt_ticks, state.total_play_ticks] == clocks
			and state.move_digest_ticks == 4
		),
		"a catch preserves run clocks and the digestion timer"
	)
	check(state.vy != -Moves.JUMP_SPEED, "a catch does not bypass the hurt input lock")
	var air := Courses.empty_world()
	state = caught_player(air)
	state.flutter_remaining = 20
	state.flutter_ready = 0
	state.vx = 400 * 60
	state.vy = -100 * 60
	state.previous_input = Bits.JUMP
	Sim.advance(state, Bits.JUMP, air)
	check(
		state.flutter_remaining == 20 and state.vy == -100 * 60 and state.vx == 256 * 60,
		"frozen flutter keeps its timer and speed but still applies its event clamp"
	)
	Sim.advance(state, 0, air)
	check(
		state.vy == -25 * 60 and state.flutter_remaining == 0 and state.flutter_cooldown == 17,
		"a frozen flutter release cuts speed and cancels without damping"
	)
	Sim.advance(state, Bits.DOWN, air)
	check(
		state.move_action == Moves.POUND_START and state.vx == 0 and state.vy == 0,
		"a frozen down event starts the pound pose without moving the body"
	)
	for count in 30:
		Sim.advance(state, Bits.DOWN, air)
	check(state.move_action_tick == 0, "a frozen pound never advances its windup")
	var ground := Courses.floor_world()
	state = caught_player(ground)
	Sim.advance(state, Bits.UP, ground)
	check(state.move_look == 1, "a frozen held up event changes posture")
	Sim.advance(state, Bits.DOWN, ground)
	check(
		state.move_duck == 1 and state.move_look == 0, "a frozen down event changes ground posture"
	)
	for count in 5:
		Sim.advance(state, Bits.DOWN, ground)
	check(state.move_posture_tick == 0, "a frozen posture never advances its animation timer")
	state.move_eggs = 2
	Sim.advance(state, Bits.THROW, ground)
	var angle: int = state.move_aim_angle
	Sim.advance(state, 0, ground)
	check(
		state.move_aim == 1 and state.move_aim_angle == angle,
		"a frozen aim starts but never sweeps with elapsed time"
	)
	Sim.advance(state, Bits.THROW, ground)
	check(
		state.move_eggs == 1 and state.move_action == Moves.TOSS and state.move_emit_serial == 1,
		"a frozen throw publishes one saved request without advancing the world"
	)


func catch_water_checks() -> void:
	var water := Courses.water_world()
	water.spawn_y = 410 * S
	var state := caught_player(water)
	var at := [state.x, state.y]
	var clocks := [state.water_wait, state.water_phase, state.move_water_transition]
	state.vy = -100 * 60
	state.previous_input = Bits.JUMP
	Sim.advance(state, 0, water)
	check(
		state.swimming == 1 and state.vy == -25 * 60,
		"frozen water still accepts a jump release without buoyancy"
	)
	for count in 5:
		Sim.advance(state, 0, water)
	check(
		(
			[state.x, state.y] == at
			and [state.water_wait, state.water_phase, state.move_water_transition] == clocks
		),
		"frozen water does not bob or advance lift and transition timers"
	)
	var flow := Courses.empty_world()
	flow.layers.append(Courses.layer("flowWater", false, false, [[3, 2]]))
	# A full downward flow over the player; it must not add continuous acceleration.
	flow.spawn_x = 112 * S
	state = caught_player(flow)
	at = [state.x, state.y]
	state.vy = 100 * 60
	for count in 5:
		Sim.advance(state, Bits.RIGHT, flow)
	check(
		[state.x, state.y] == at and state.vy == 100 * 60,
		"frozen flow does not push the body or add gravity"
	)
	flow.layers[0].cells[2 * 32 + 3] = 4
	Sim.advance(state, 0, flow)
	check([state.x, state.y] == at, "a frozen sideways flow never translates the body")
	flow.layers[0].cells[2 * 32 + 3] = 6
	state.vx = 100 * 60
	Sim.advance(state, Bits.JUMP, flow)
	check(
		[state.x, state.y] == at and state.vx == -400 * 60 and state.vy == -Moves.JUMP_SPEED,
		"a frozen sloped-flow jump changes velocity without its opposing-speed or flow pushes"
	)


func catch_buffered_jump_checks() -> void:
	var world := Courses.floor_world()
	var state := caught_player(world)
	# A landing can start a buffered jump just before contact catches the companion.
	Moves.jump(state)
	state.move_jump_carry = 1
	state.previous_input = Bits.JUMP
	Sim.advance(state, 0, world)
	check(
		state.vy == -Moves.JUMP_SPEED / 4 and state.move_jump_carry == 0,
		"the catch consumes a pending landing-jump event before its release"
	)
	for count in Life.REJOIN_STEPS - 1:
		Sim.advance(state, 0, world)
	check(
		state.life_phase == Life.PLAY and state.vy == -Moves.JUMP_SPEED / 4,
		"a landing-jump release is not overwritten by a carried full jump after the catch"
	)


func catch_request_checks() -> void:
	var world := Courses.empty_world()
	var state := caught_player(world)
	state.move_eggs = 6
	var restored := {}
	var restored_world := world.duplicate(true)
	for count in 6:
		if count == 3:
			var decoded := Snapshot.decode(Snapshot.encode(state), world.identity)
			check(decoded.ok, "a catch with pending future throws restores from a snapshot")
			restored = decoded.get("state", {})
		for input: int in [Bits.THROW, 0, Bits.THROW, 0]:
			Sim.advance(state, input, world)
			if not restored.is_empty():
				Sim.advance(restored, input, restored_world)
	check(
		state == restored, "restoring during frozen throws preserves all subsequent input effects"
	)
	check(
		(
			state.entities.size() == 6
			and state.move_eggs == 0
			and state.egg_request_cursor == state.move_emit_serial
		),
		"frozen throws consume each event before the saved request history can overflow"
	)
	var all_frozen := true
	for entity: Dictionary in state.entities:
		all_frozen = all_frozen and entity.x == state.x and entity.y == state.y - 32 * S
	check(all_frozen, "actors created by frozen input events never advance or move")
	check(
		Snapshot.decode(Snapshot.encode(state), world.identity).ok,
		"actors created by frozen input events remain valid saved state"
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
