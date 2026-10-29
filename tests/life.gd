extends SceneTree
## Pure synthetic lifecycle checks. No game scenes, recordings or rendering.

const Life = preload("res://src/sim/life.gd")
const Damage = preload("res://src/sim/damage.gd")
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/sim/collision.gd")
const S := 3600
var assertions := 0
var failures := 0


func _initialize() -> void:
	damage_checks()
	companion_checks()
	bubble_contact_checks()
	countdown_checks()
	rescue_checks()
	rescue_spawn_checks()
	death_checks()
	checkpoint_checks()
	goal_checks()
	clock_checks()
	validation_checks()
	print("LIFE_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func damage_checks() -> void:
	var world := course()
	var state := player(world)
	state.vx = 400 * 60
	Damage.hurt(state, state.x + 100 * S)
	check(
		state.vx == -656 * 60 and state.vy == -384 * 60, "Damage reverses velocity before knockback"
	)
	check(
		state.invulnerable == Life.IMMUNITY and state.hurt == Life.KNOCKED_LOCK,
		"Damage starts immunity and first hurt lock"
	)
	check(
		state.separated == 1 and state.companion_mode == Life.LAUNCH, "Hit separates the companion"
	)
	check(state.companion_dx == 164 * S, "Launch distance uses final knockback velocity")
	check(
		state.health == 10 and state.health_wait == Life.COUNTDOWN_STEPS,
		"Damage starts a countdown without consuming health"
	)
	check(state.hits == 1, "A separation counts once")
	Damage.hurt(state, state.x)
	check(state.hits == 1 and state.vx == -656 * 60, "Immunity rejects another hit")
	state.invulnerable = 0
	state.health_wait = 17
	Damage.hurt(state, state.x - 100 * S)
	check(
		state.hurt == Life.SPIN_LOCK and state.health_wait == 17,
		"Separated hit keeps countdown progress"
	)
	check(state.hits == 1, "Separated hit is not a second companion loss")
	state = player(world)
	state.swimming = 1
	state.facing = -1
	Damage.hurt(state, state.x + S)
	check(
		state.vx == 200 * 60 and state.companion_dx == -112 * S,
		"Water knockback uses facing then launch clamp"
	)
	check(state.hurt == 0, "First swimming hit separates without a dry-land hurt lock")
	state.invulnerable = 0
	Damage.hurt(state, state.x + S)
	check(state.hurt == Life.SPIN_LOCK, "Already-separated swimming hit uses the spin lock")
	check(
		state.hurt_deceleration == 128 and Life.valid_state(state),
		"Swimming spin keeps the water deceleration in valid state"
	)
	state = player(world)
	Damage.separate(state, 0)
	check(
		state.companion_mode == Life.BUBBLE and state.recovery_delay == 0,
		"Capture separation makes an instant bubble"
	)


func companion_checks() -> void:
	var world := course()
	var state := player(world)
	Damage.hurt(state, state.x + S)
	var start_x: int = state.recovery_x
	var start_y: int = state.recovery_y
	for tick in 18:
		step(state, world)
	check(state.recovery_y == start_y - 56 * S, "Launch reaches its apex in eighteen ticks")
	check(state.recovery_x == start_x + 56 * S, "Launch travels horizontally during the arc")
	for tick in 18:
		step(state, world)
	check(
		state.companion_mode == Life.LAUNCH and state.recovery_y == start_y,
		"Launch returns to its initial height after thirty-six ticks"
	)
	for tick in Life.LAUNCH_STEPS - 36:
		step(state, world)
	check(state.companion_mode == Life.BUBBLE, "The bubble forms two ticks after the arc")
	check(
		state.recovery_y == start_y and state.recovery_x == start_x + 112 * S,
		"The bubble forms where the arc ended"
	)
	start_x = state.recovery_x
	for tick in 60:
		step(state, world)
	check(state.recovery_x > start_x, "Free bubble drifts instead of remaining a marker")
	check(state.companion_vx == 48 * 60, "Bubble horizontal speed cap")
	check(state.companion_vy == -192 * 60, "Bubble initial vertical ramp takes one second")
	# The swing holds the ramp's last speed for one step, then reverses over two seconds.
	step(state, world)
	check(state.companion_vy == -192 * 60, "The swing starts one step after the ramp")
	for tick in 120:
		step(state, world)
	check(state.companion_vy == 192 * 60, "Bubble vertical motion reverses over a two-second leg")
	var restored: Dictionary = state.duplicate(true)
	for tick in 60:
		step(state, world)
		step(restored, world)
	check(state == restored, "All companion future motion comes from declared state")


func bubble_contact_checks() -> void:
	var world := course()
	var cells := PackedInt32Array()
	cells.resize(15 * 9)
	cells.fill(-1)
	for row in 9:
		cells[row * 15 + 5] = 0
	world.layers = [solid_layer(cells, 15, 9)]
	var state := player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 124 * S
	state.recovery_y = 200 * S
	state.companion_direction = 1
	state.companion_vx = 48 * 60
	for tick in 30:
		step(state, world)
	check(
		state.companion_direction == -1 and state.companion_vx < 0, "Bubble turns at terrain walls"
	)
	check(state.recovery_x + 30 * S < 160 * S, "Bubble stays outside the wall")
	cells.fill(-1)
	cells[5 * 15 + 5] = 0
	world.layers = [solid_layer(cells, 15, 9)]
	state = player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 176 * S
	state.recovery_y = 200 * S
	for tick in 30:
		step(state, world)
	check(
		state.recovery_x != 176 * S or state.recovery_y != 200 * S,
		"An embedded bubble escapes instead of remaining stuck"
	)
	# Terrain sees the bubble's octagon, not its bounding box: a block at its corner is clear.
	var corner := {"x": 135 * S, "y": 165 * S}
	check(
		(
			Collision.overlaps(corner, world, Life.BUBBLE_BOX)
			and not Collision.overlaps(corner, world, Life._bubble_body())
		),
		"A block beside the bubble's cut corner does not touch it"
	)
	corner.x = 150 * S
	check(Collision.overlaps(corner, world, Life._bubble_body()), "Its side still meets the block")
	# A bubble that forms inside a block is pushed out on the step it forms.
	state = player(world)
	Damage.hurt(state, state.x + S)
	state.companion_age = Life.LAUNCH_STEPS - 1
	# The bubble box ends 6 px inside the block's top.
	state.companion_from_x = 176 * S
	state.companion_from_y = 166 * S
	state.companion_dx = 0
	step(state, world)
	check(state.companion_mode == Life.BUBBLE, "The bubble forms on its launch step")
	check(
		not World.overlaps_box(
			world,
			state.recovery_x - 30 * S,
			state.recovery_y - 60 * S,
			state.recovery_x + 30 * S,
			state.recovery_y
		),
		"A bubble that forms in a block is pushed out at once"
	)
	# Deep inside terrain it drifts toward the player on both axes.
	var solid := PackedInt32Array()
	solid.resize(15 * 9)
	solid.fill(0)
	world.layers = [solid_layer(solid, 15, 9)]
	state = player(world)
	Life.separate(state, 0, true)
	state.x = 64 * S
	state.y = 100 * S
	state.recovery_x = 300 * S
	state.recovery_y = 250 * S
	state.companion_age = 100
	step(state, world)
	check(
		state.recovery_x == 300 * S - 96 * 60 and state.recovery_y < 250 * S,
		"An embedded bubble drifts toward the player"
	)
	cells.fill(-1)
	for column in 15:
		cells[15 + column] = 0
	world.layers = [solid_layer(cells, 15, 9)]
	state = player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 250 * S
	state.recovery_y = 130 * S
	for tick in 60:
		step(state, world)
	check(state.recovery_y - 60 * S > 64 * S, "Bubble pushes down from ceilings")
	check(state.recovery_y - 124 * S <= S / 16, "Bubble ceiling contact uses shared precision")
	world.layers.clear()
	state = player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 10 * S
	state.recovery_y = 200 * S
	step(state, world)
	check(
		not Life.catch_companion(state, 0, 100 * S, 64 * S, 220 * S),
		"Bubble cannot be caught during its border correction"
	)
	for tick in 6:
		step(state, world)
	check(
		Life.catch_companion(state, 0, 100 * S, 64 * S, 220 * S),
		"Bubble catch resumes after border correction"
	)
	var layer := solid_layer(PackedInt32Array([0]), 1, 1)
	layer.name = "lava"
	layer.solid = false
	var points := PackedInt64Array([32 * S, 0, 32 * S, 32 * S, 0, 32 * S])
	layer.polygons[0] = points
	world.layers = [layer]
	state = player(world)
	state.x = 2 * S
	state.y = 2 * S
	Life.after_step(state, world)
	check(state.life_phase == Life.PLAY, "Lethal terrain uses its polygon, not its bounding box")
	state.x = 24 * S
	state.y = 20 * S
	state.invulnerable = 120
	Life.after_step(state, world)
	check(
		state.death_cause == Life.HAZARD and state.life_phase == Life.DEAD,
		"Lethal terrain ignores flashing immunity"
	)


func countdown_checks() -> void:
	var world := course()
	var state := player(world)
	Life.separate(state, 0)
	for tick in Life.COUNTDOWN_STEPS - 1:
		step(state, world)
	check(state.health == 10, "Countdown waits the full first interval")
	step(state, world)
	check(
		state.health == 9 and state.health_wait == Life.COUNTDOWN_STEPS,
		"Countdown consumes one unit per forty-six ticks"
	)
	var item := {"collected": 0}
	check(Life.collect(state, Life.STAR, item), "Star pickup is accepted")
	check(state.health == 10 and item.collected == 1, "Star pickup adds one countdown unit")
	check(not Life.collect(state, Life.STAR, item), "A collected item cannot count twice")
	state.health = 30
	Life.collect(state, Life.STAR)
	check(state.health == 30, "Collectable refill is capped at thirty")
	state = player(world)
	state.health = 8
	state.health_wait = 120
	for tick in 119:
		step(state, world)
	check(state.health == 8, "Automatic refill waits two seconds")
	step(state, world)
	check(state.health == 9, "Automatic refill adds one unit")
	for tick in 120:
		step(state, world)
	check(state.health == 10 and state.health_wait == 0, "Automatic refill stops at ten")


func rescue_checks() -> void:
	var world := course()
	# A map wide enough for a far follow point: the screen centre stays inside it.
	var wide := course()
	wide.width = 4000000000000
	var far := player(wide)
	Life.separate(far, 0, true)
	far.recovery_x = 1000 * S
	far.recovery_y = 200 * S
	far.health = 1
	far.health_wait = 1
	far.camera_x = 1000000000000
	var far_start: int = far.camera_x - 120 * S
	step(far, wide)
	check(far.rescue_1_x == far_start, "Captors appear without moving on the step they come")
	step(far, wide)
	check(
		far.rescue_1_x < far_start and far.rescue_1_x >= far_start - 1024 * 60,
		(
			"Distant capture pursuit avoids squared-distance overflow (%d -> %d)"
			% [far_start, far.rescue_1_x]
		)
	)
	var state := player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 1000 * S
	state.recovery_y = 200 * S
	state.health = 1
	state.health_wait = 1
	step(state, world)
	check(state.health == 0 and state.rescue_active == 1, "Zero starts the last rescue window")
	# The course is 448 px high: the screen centre is held at 224 px, and at x 64 the
	# centre is held 416 px from the left edge.
	check(
		(
			absi(state.rescue_4_x - (416 + 120) * S) <= 1024 * 60
			and absi(state.rescue_4_y - (224 - 304) * S) <= 1024 * 60
		),
		"Capture agents start from the clamped screen centre and pursue at once"
	)
	check(
		state.life_phase == Life.PLAY and state.deaths == 0,
		"Zero does not immediately reset the run"
	)
	check(
		Life.catch_companion(state, 980 * S, 140 * S, 1020 * S, 201 * S),
		"The companion can be caught at zero"
	)
	check(
		state.life_phase == Life.REJOIN and state.life_ticks == Life.REJOIN_STEPS,
		"Catch starts the two-leg return sequence"
	)
	for tick in Life.REJOIN_STEPS - 1:
		step(state, world)
	check(
		state.separated == 1 and state.health == 0, "Countdown and play pause during reattachment"
	)
	step(state, world)
	check(
		state.separated == 0 and state.life_phase == Life.PLAY,
		"Reattachment restores the carried companion"
	)
	check(
		state.separation_grace == 30 and state.health_wait == 120,
		"Reattachment starts grace and refill timers"
	)
	for tick in 120:
		step(state, world)
	check(state.health == 1, "Zero-health rescue can regenerate")
	state = player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 1000 * S
	state.recovery_y = 200 * S
	state.health = 1
	state.health_wait = 1
	step(state, world)
	Life.collect(state, Life.STAR)
	step(state, world)
	check(
		(
			state.health == 1
			and state.health_wait == Life.COUNTDOWN_STEPS - 1
			and state.rescue_active == 1
		),
		"Refill at zero restarts the interval, not the capture helpers"
	)
	state = player(world)
	Life.separate(state, 0, true)
	state.recovery_x = 1000 * S
	state.recovery_y = 200 * S
	state.health = 1
	state.health_wait = 1
	step(state, world)
	var ticks := 0
	while state.companion_mode != Life.TAKEN and ticks < 120:
		step(state, world)
		ticks += 1
	check(
		ticks > 1 and ticks < 120 and state.rescue_mask == 15,
		"Capture agents arrive in finite simulation time"
	)
	check(state.rescue_ticks == 90, "Capture leaves a ninety-tick departure sequence")
	for tick in 89:
		step(state, world)
	check(state.deaths == 0, "Departure is not instant death")
	step(state, world)
	check(
		state.life_phase == Life.DEAD and state.death_cause == Life.COUNTDOWN,
		"Failed rescue enters the death sequence"
	)


func rescue_spawn_checks() -> void:
	var world := course()
	world.width = 4000 * S
	world.height = 2000 * S
	var fresh := player(world)
	fresh.x = 2000 * S
	fresh.y = 1000 * S
	fresh.camera_x = fresh.x
	fresh.camera_y = fresh.y - 28 * S
	fresh.health = 0
	Life.separate(fresh, 0, true, world)
	check(
		fresh.rescue_active == 1 and fresh.rescue_1_y == (1000 - 64 - 304) * S,
		"Mid-map captors start 304 px above the screen centre, 64 px above the player"
	)
	check(
		(
			fresh.rescue_1_x == (2000 - 120) * S
			and fresh.rescue_2_x == (2000 - 24) * S
			and fresh.rescue_3_x == (2000 + 24) * S
			and fresh.rescue_4_x == (2000 + 120) * S
		),
		"Mid-map captors spread around the player's x"
	)
	var edge := player(world)
	edge.x = 100 * S
	edge.y = 1950 * S
	edge.camera_x = edge.x
	edge.camera_y = edge.y - 28 * S
	edge.health = 0
	Life.separate(edge, 0, true, world)
	check(
		edge.rescue_1_x == (416 - 120) * S and edge.rescue_1_y == (2000 - 224 - 304) * S,
		"Near a corner the captors start from the screen held inside the map"
	)
	var deferred := player(world)
	deferred.health = 0
	Life.separate(deferred, 0, true)
	# Keep the bubble away from the player so contact does not catch it.
	deferred.recovery_x = 1000 * S
	deferred.recovery_y = 600 * S
	check(deferred.rescue_active == 0, "Without the world the summons waits for the step")
	Life.before_step(deferred, world)
	check(deferred.rescue_active == 1, "The next companion step summons the captors")


func death_checks() -> void:
	var world := course()
	var state := player(world)
	state.invulnerable = 120
	state.y = world.height + 67 * S  # Past the 66 px line of a falling body.
	Life.after_step(state, world)
	check(
		state.life_phase == Life.DEAD and state.deaths == 1, "Pit death bypasses contact immunity"
	)
	check(state.y != world.spawn_y, "Death does not teleport immediately")
	for tick in 239:
		step(state, world)
	check(state.life_phase == Life.DEAD, "Ordinary death waits four seconds")
	step(state, world)
	check(
		state.life_phase == Life.FADE_OUT and state.life_ticks == Life.DEATH_FADE,
		"Ordinary death fades for one second"
	)
	for tick in Life.DEATH_FADE - 1:
		step(state, world)
	check(state.life_phase == Life.FADE_OUT, "The fade holds until its last step")
	step(state, world)
	check(
		state.life_phase == Life.FADE_IN and state.x == world.spawn_x and state.y == world.spawn_y,
		"Respawn rebuilds and places the player"
	)
	check(
		state.health == 10 and state.deaths == 1, "Respawn resets countdown but keeps death count"
	)
	check(Life.blocks_step(state) and Life.locks_input(state), "The respawn step holds the body")
	step(state, world)
	check(Life.blocks_step(state), "The first restart step holds the body")
	step(state, world)
	check(
		not Life.blocks_step(state) and Life.locks_input(state),
		"The second restart step moves the body without input"
	)
	step(state, world)
	check(
		state.life_phase == Life.PLAY and not Life.locks_input(state),
		"Input works on the third step after the respawn"
	)
	state = player(world)
	state.hits = 4
	state.quick_death = 1
	check(Life.kill(state, Life.HAZARD), "Lethal hazard bypasses the ordinary damage path")
	check(not Life.kill(state, Life.HAZARD), "One death cannot be counted twice")
	check(state.life_ticks == Life.QUICK_FADE, "Quick death fades for half a second")
	for tick in Life.QUICK_FADE:
		step(state, world)
	check(
		state.life_phase == Life.FADE_IN and state.hits == 4 and state.quick_death == 1,
		"Quick death keeps run counters and preference"
	)
	state = player(world)
	Life.quick_restart(state)
	for tick in Life.QUICK_FADE:
		Life.before_step(state, world)
	check(
		state.life_phase == Life.RESPAWN,
		"Missing reset integration leaves an explicit pending phase"
	)
	check(
		Life.before_step(state, world, reset_entities, change_map),
		"Lifecycle reports the exact respawn tick"
	)
	check(
		not Life.before_step(state, world, reset_entities, change_map),
		"A fade tick does not report another respawn"
	)
	check(Life.blocks_step(state), "Respawn fade blocks ordinary simulation input")


func checkpoint_checks() -> void:
	var world := course()
	var state := player(world)
	state.x = 200 * S
	state.health = 8
	state.coins = 50
	state.redcoins = 2
	state.flowers = 1
	var checkpoint := {
		"id": "checkpoint-anchor",
		"source_index": 1,
		"map_index": 1,
		"x": 200 * S,
		"y": 320 * S,
		"respawn_x": 350 * S,
		"respawn_y": 300 * S,
		"health_bonus": 10,
		"collected": 0,
		"checkpoint_collected": 0
	}
	state.entities = [
		{"id": "coin", "source_index": 0, "collected": 1, "checkpoint_collected": 0},
		checkpoint,
		{"id": "flower", "source_index": 2, "collected": 0, "checkpoint_collected": 0}
	]
	check(Life.touch_checkpoint(state, checkpoint), "Checkpoint accepts contact near its center")
	check(
		state.checkpoint_x == 350 * S and state.checkpoint_y == 300 * S,
		"Checkpoint uses its explicit respawn coordinates"
	)
	check(state.checkpoint_id == 2, "Checkpoint stores a one-based source index, not its string id")
	check(
		state.entities[0].checkpoint_collected == 1 and checkpoint.checkpoint_collected == 1,
		"Checkpoint saves picked-up entity flags"
	)
	for tick in 60:
		step(state, world)
	check(
		state.health == 18 and state.checkpoint_health == 18,
		"Checkpoint grants ten units at six-tick intervals"
	)
	for tick in 45:
		step(state, world)
	check(
		state.life_phase == Life.PLAY, "Checkpoint releases the play pause after its exit sequence"
	)
	Life.collect(state, Life.RED_COIN, state.entities[2])
	Life.collect(state, Life.COIN)
	Life.collect(state, Life.FLOWER)
	Life.quick_restart(state)
	for tick in Life.QUICK_FADE:
		step(state, world)
	check(
		state.x == 350 * S and state.y == 300 * S and state.health == 18,
		"Respawn uses checkpoint position and saved countdown"
	)
	check(
		state.redcoins == 2 and state.flowers == 1 and state.coins == 51,
		"Respawn restores scored pickups and keeps ordinary coins"
	)
	check(
		(
			state.entities[0].collected == 1
			and state.entities[1].collected == 1
			and state.entities[2].collected == 0
		),
		"Respawn rolls pickup flags back to checkpoint"
	)
	check(
		not Life.touch_checkpoint(state, state.entities[1]),
		"Saved checkpoint cannot activate twice"
	)
	state.life_phase = Life.PLAY
	state.map_index = 2
	state.checkpoint_map = 1
	Life.quick_restart(state)
	for tick in Life.QUICK_FADE:
		step(state, world)
	check(
		state.map_index == 1 and state.x == 350 * S,
		"Cross-map checkpoint uses the supplied map-change boundary"
	)
	state = player(world)
	state.x = 200 * S
	state.health = 29
	state.invulnerable = 100
	checkpoint.collected = 0
	checkpoint.health_bonus = 30
	state.entities = [checkpoint]
	check(Life.touch_checkpoint(state, checkpoint), "Full-refill checkpoint accepts contact")
	for tick in 51:
		step(state, world)
	check(
		state.health == 30 and state.checkpoint_health == 30,
		"Full checkpoint stops at the countdown cap"
	)
	check(
		state.life_phase == Life.PLAY and state.invulnerable == 100,
		"Checkpoint freezes ordinary immunity timers"
	)
	state = player(world)
	state.x = 200 * S
	Life.separate(state, 0, true)
	state.recovery_x = 800 * S
	state.recovery_y = 200 * S
	state.health = 30
	checkpoint.collected = 0
	checkpoint.health_bonus = 10
	state.entities = [checkpoint]
	check(
		Life.touch_checkpoint(state, checkpoint) and state.health_wait == 60,
		"Checkpoint recreates a separated meter with a one-second first interval"
	)
	for tick in 45 + 59:
		step(state, world)
	check(
		state.health == 30 and state.health_wait == 1,
		"Checkpoint time does not consume its first countdown interval"
	)
	step(state, world)
	check(
		state.health == 29 and state.health_wait == Life.COUNTDOWN_STEPS,
		"Separated checkpoint meter returns to ordinary countdown intervals"
	)


func goal_checks() -> void:
	var world := course()
	var state := player(world)
	var goal := {"x": 400 * S, "y": 200 * S}
	state.separated = 1
	check(not Life.touch_goal(state, goal), "Goal requires the carried companion")
	state.separated = 0
	check(Life.touch_goal(state, goal), "Goal contact starts the sequence")
	Life.goal_coin(state)
	check(state.coins == 1, "Goal conversion hook awards an ordinary coin")
	for tick in 60:
		step(state, world)
	check(
		state.x == 400 * S and state.y == 232 * S,
		"Goal approach reaches the sensor anchor in one second"
	)
	check(state.goal_reached == 0, "Goal contact does not freeze before the sequence finishes")
	for tick in 119:
		step(state, world)
	check(state.goal_reached == 0, "Goal waits for the score presentation")
	step(state, world)
	check(
		state.goal_reached == 1 and state.life_phase == Life.COMPLETE,
		"Goal completes after the score sequence"
	)
	state.health = 30
	state.redcoins = 20
	state.flowers = 5
	check(Life.score(state) == 100, "Run score combines countdown, red coins and flowers")
	Life.goal_coin(state)
	check(state.coins == 1, "Goal conversion cannot award coins outside its sequence")


func clock_checks() -> void:
	var world := course()
	var state := player(world)
	for tick in 5:
		step(state, world)
	check(
		state.attempt_ticks == 5 and state.play_ticks == 5 and state.total_play_ticks == 5,
		"Run clocks advance only during play"
	)
	state.health = 30
	var checkpoint := {
		"id": "clock-point",
		"source_index": 0,
		"x": state.x,
		"y": state.y,
		"respawn_x": state.x,
		"respawn_y": state.y,
		"health_bonus": 10,
		"collected": 0
	}
	state.entities = [checkpoint]
	Life.touch_checkpoint(state, checkpoint)
	for tick in 45:
		step(state, world)
	check(
		state.attempt_ticks == 5 and state.play_ticks == 5 and state.total_play_ticks == 5,
		"Checkpoint sequence pauses all clocks"
	)
	for tick in 7:
		step(state, world)
	Life.quick_restart(state)
	for tick in Life.QUICK_FADE + Life.RESTART_STEPS:
		step(state, world)
	check(
		state.attempt_ticks == 0 and state.play_ticks == 5 and state.total_play_ticks == 12,
		"Respawn resets attempt time, restores checkpoint time and keeps total time"
	)
	state.attempt_ticks = Life.MAX_COUNT
	state.play_ticks = Life.MAX_COUNT
	state.total_play_ticks = Life.MAX_COUNT
	step(state, world)
	check(
		(
			state.attempt_ticks == Life.MAX_COUNT
			and state.play_ticks == Life.MAX_COUNT
			and state.total_play_ticks == Life.MAX_COUNT
		),
		"Run clocks saturate instead of wrapping"
	)


func validation_checks() -> void:
	var world := course()
	var state := player(world)
	state.map_count = 1
	check(Life.valid_state(state), "Fresh lifecycle state validates")
	for fields: Array in [Life.PLAYER_FIELDS, Life.LEVEL_FIELDS]:
		for field: Array in fields:
			var broken := state.duplicate(true)
			broken[field[0]] = 0.5
			check(not Life.valid_state(broken), "Lifecycle fields reject floats: " + field[0])
	for pair: Array in [
		["health", -1],
		["health", 31],
		["life_phase", 99],
		["life_ticks", -1],
		["rescue_mask", 16],
		["checkpoint_id", 99],
		["coins", -1],
		["health_wait", 1.5],
		["recovery_x", Life.MAX_COUNT],
		["separated", 1],
		["run_spawn_map", 2],
		["companion_age", 301],
		["bubble_bound_ticks", 7],
		["companion_vx", 48 * 60 + 1],
		["goal_reached", 1]
	]:
		var broken := state.duplicate(true)
		broken[pair[0]] = pair[1]
		check(not Life.valid_state(broken), "Impossible lifecycle value rejected: " + pair[0])


func step(state: Dictionary, world: Dictionary) -> void:
	Life.before_step(state, world, reset_entities, change_map)


func reset_entities(state: Dictionary, _world: Dictionary, keep_flags: bool = false) -> void:
	var rebuilt := []
	for item: Dictionary in state.entities:
		rebuilt.append(
			{
				"id": item.id,
				"source_index": item.source_index,
				"collected": int(item.get("checkpoint_collected", 0)) if keep_flags else 0,
				"checkpoint_collected":
				int(item.get("checkpoint_collected", 0)) if keep_flags else 0
			}
		)
	state.entities = rebuilt


func change_map(state: Dictionary, world: Dictionary, map_index: int, x: int, y: int) -> void:
	state.map_index = map_index
	reset_entities(state, world)
	state.x = x
	state.y = y


func solid_layer(cells: PackedInt32Array, width: int, height: int) -> Dictionary:
	return {
		"name": "unit",
		"layer": "layer1",
		"size": 32,
		"width": width,
		"height": height,
		"cells": cells,
		"bounds": {0: [0, 0, 32 * S, 32 * S]},
		"polygons": {0: PackedInt64Array([0, 0, 32 * S, 0, 32 * S, 32 * S, 0, 32 * S])},
		"solid": true,
		"water": false
	}


func course() -> Dictionary:
	return {
		"width": 2000 * S,
		"height": 448 * S,
		"spawn_x": 64 * S,
		"spawn_y": 352 * S,
		"layers": [],
		"bridges": []
	}


func player(world: Dictionary) -> Dictionary:
	var state := {
		"x": world.spawn_x,
		"y": world.spawn_y,
		"vx": 0,
		"vy": 0,
		"camera_x": world.spawn_x,
		"camera_y": world.spawn_y - 28 * S,
		"facing": 1,
		"on_floor": 0,
		"swimming": 0,
		"captured_by": 0,
		"jump_buffer": 0,
		"flutter_remaining": 0,
		"deaths": 0,
		"goal_reached": 0,
		"movement": 0,
		"map_index": 1,
		"entities": []
	}
	Life.initialize(state, world)
	return state


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
