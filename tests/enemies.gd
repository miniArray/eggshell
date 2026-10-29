extends SceneTree
## Focused contract tests; controlled states are fixtures, never recording inputs.

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Save = preload("res://src/save/snapshot.gd")
const Damage = preload("res://src/sim/damage.gd")
const Life = preload("res://src/sim/life.gd")
const Registry = preload("res://src/sim/registry.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Collision = preload("res://src/level/collision_table.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const S := State.SCALE
var assertions := 0
var failures := 0


func _initialize() -> void:
	var world: Dictionary = Fixtures.world()
	var counts := {}
	for enemy: Dictionary in world.enemies:
		counts[enemy.code] = counts.get(enemy.code, 0) + 1
	check(counts == {"e1": 1, "e2": 1, "e3": 1, "e5": 1, "e20": 1}, "Full enemy inventory")
	for code: String in ["e1", "e2", "e3", "e5", "e20"]:
		movement_and_contact(world, code)
	movement_constants(world)
	fall_integration_checks()
	bounce_checks(world)
	damage_checks(world)
	leap_and_capture_checks(world)
	lifecycle_checks(world)
	boundary_checks(Fixtures.code())
	print("ENEMY_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func fixture(world: Dictionary, code: String) -> Dictionary:
	var result := world.duplicate(true)
	var cells := PackedInt32Array()
	cells.resize(32 * 12)
	cells.fill(-1)
	for column in 32:
		cells[32 * 11 + column] = 0
	result.layers = [
		{
			"name": "unit",
			"layer": "layer1",
			"size": 32,
			"width": 32,
			"height": 12,
			"cells": cells,
			"bounds": {0: [0, 0, 32 * S, 32 * S]},
			"polygons": {0: PackedInt64Array([0, 0, 32 * S, 0, 32 * S, 32 * S, 0, 32 * S])},
			"solid": true,
			"water": false
		}
	]
	result.height = 2000 * S
	for enemy: Dictionary in world.enemies:
		if enemy.code == code:
			var record: Dictionary = enemy.properties.duplicate(true)
			record.X = 400
			record.Y = 300
			var compiled := World.setup_objects({"objects": {"actor": record}}, result)
			check(compiled.ok, "Isolated actor compiles through the registry")
			break
	if code == "e20":
		var water: Dictionary = result.layers[0].duplicate(true)
		water.solid = false
		water.water = true
		for column in 32:
			water.cells[32 * 9 + column] = 0
			water.cells[32 * 10 + column] = 0
		result.layers.append(water)
	result.spawn_x = 200 * S
	result.spawn_y = 300 * S
	result.erase("maps")
	result.maps = {1: result.duplicate()}
	return result


func movement_and_contact(world: Dictionary, code: String) -> void:
	var test_world := fixture(world, code)
	var state := _placed_state(test_world)
	var first: Dictionary = state.enemies[0].duplicate()
	for tick in 180:
		Sim.advance(state, 0, test_world)
	check(state.enemies[0].status == 1, code + " activates near the saved camera")
	check(state.enemies[0].x != first.x or state.enemies[0].y != first.y, code + " moves")
	state = _placed_state(test_world)
	state.x = 400 * S
	state.y = 330 * S
	Sim.advance(state, 0, test_world)
	if code == "e5":
		# Ground plant's head reaches toward a player above its stem, not its harmless base.
		state.x = 430 * S
		state.y = 290 * S
		for tick in 20:
			Sim.advance(state, 0, test_world)
		check(state.captured_by == 1, "Plant captures rather than permitting a stomp")
		check(state.hits == 0, "A capture is not a hurt until the companion is lost")
	else:
		check(state.hits == 1 and state.deaths == 0, code + " side contact hurts, not kills")
		check(state.invulnerable == Life.IMMUNITY and state.vy == -384 * 60, code + " hurt impulse")
	var restored := Save.decode(Save.encode(state), test_world.identity)
	check(restored.ok and restored.state == state, code + " active state round trip")
	for tick in 90:
		Sim.advance(state, Sim.RIGHT | Sim.JUMP, test_world)
		Sim.advance(restored.state, Sim.RIGHT | Sim.JUMP, test_world)
	check(Save.encode(state) == Save.encode(restored.state), code + " future matches restore")


func movement_constants(world: Dictionary) -> void:
	var test_world := fixture(world, "e1")
	var player := _placed_state(test_world)
	for tick in 150:
		Sim.advance(player, 0, test_world)
		if player.enemies[0].mode == 1:
			break
	check(absi(player.enemies[0].vx) == 48 * 60, "Walker assigns 48 px/s after its idle wait")
	test_world = fixture(world, "e2")
	player = _placed_state(test_world)
	# The step that wakes an object does not move it; 180 moves follow.
	for tick in 181:
		Sim.advance(player, 0, test_world)
	# The swing tweens -128 to 128 px/s, capped at the body's 48 px/s top speed.
	check(
		player.enemies[0].vx == 48 * 60,
		"Flyer swings at its capped top speed near the tween endpoint"
	)
	var wave: int = Motion.sine((player.frame + Motion.LEVEL_INTRO_TICKS) % 180, 180, 12 * S)
	check(
		player.enemies[0].y == 300 * S + wave,
		"Flyer bobs on the level clock, three seconds per period, from the level intro"
	)
	test_world = fixture(world, "e3")
	player = _placed_state(test_world)
	# It wakes in the first step and first moves in the second.
	Sim.advance(player, 0, test_world)
	Sim.advance(player, 0, test_world)
	check(player.enemies[0].vx == -48 * 60, "Flower starts walking at 48 px/s")
	test_world = fixture(world, "e20")
	player = _placed_state(test_world)
	var reached_cap := false
	var within_cap := true
	for tick in 90:
		Sim.advance(player, 0, test_world)
		reached_cap = reached_cap or absi(player.enemies[0].vx) == 128 * 60
		within_cap = within_cap and absi(player.enemies[0].vx) <= 128 * 60
	check(reached_cap and within_cap, "Fish accelerates to, but never exceeds, swim cap")
	test_world = fixture(world, "e5")
	player = _placed_state(test_world)
	for tick in 22:
		Sim.advance(player, 0, test_world)
	check(
		player.enemies[0].x == 400 * S and player.enemies[0].head_size == 15,
		"Plant stays rooted horizontally and grows its head in fifteen ticks"
	)


func fall_integration_checks() -> void:
	# Platform order: a body at rest that loses its floor gains speed before it moves,
	# and each move uses the mean of the step's old and new speed.
	var open_air := {"layers": [], "bridges": [], "width": 4096 * S, "height": 4096 * S}
	var body := {"code": "e3", "x": 512 * S, "y": 512 * S, "vx": 0, "vy": 0}
	var box := [-14 * S, -34 * S, 14 * S, 16 * S]
	var y: int = body.y
	Motion.gravity_box(body, open_air, box)
	check(body.y == y and body.vy == 2048, "Falling enemy does not move on its first step")
	Motion.gravity_box(body, open_air, box)
	check(body.y == y + 2048 + 1024 and body.vy == 4096, "Fall moves by the mean speed")


func bounce_checks(world: Dictionary) -> void:
	for code: String in ["e1", "e2", "e3", "e20"]:
		for held: bool in [false, true]:
			var test_world := fixture(world, code)
			var state := _placed_state(test_world)
			state.x = 400 * S
			state.y = 291 * S
			state.vy = 100 * 60
			Sim.advance(state, Sim.JUMP if held else 0, test_world)
			var enemy: Dictionary = state.enemies[0]
			var expected := -absi(enemy.vy / 2) - (704 if held else 320) * 60
			check(state.vy == expected, code + " relative enemy bounce")
			check(state.boosted_flutter == 1 and state.flutter_ready == 1, code + " grants boost")
			check(enemy.status == 3 and state.hits == 0, code + " stomp defeats without damage")
			Sim.advance(state, 0, test_world)
			check(
				state.boosted_flutter == 1, code + " release guard preserves a fresh bounce boost"
			)
	var boosted := _placed_state(fixture(world, "e1"))
	boosted.boosted_flutter = 1
	boosted.flutter_ready = 1
	boosted.vy = 300 * 60
	boosted.enemies.clear()
	var empty := fixture(world, "e1")
	empty.enemies.clear()
	Sim.advance(boosted, Sim.JUMP, empty)
	check(
		boosted.flutter_remaining == 50 and boosted.vy < 300 * 60, "Boosted flutter lasts 51 steps"
	)


func damage_checks(world: Dictionary) -> void:
	var test_world := fixture(world, "e1")
	var state := _placed_state(test_world)
	state.x = 400 * S
	state.y = 330 * S
	Sim.advance(state, 0, test_world)
	check(state.health == 10 and state.separated == 1, "Hit starts countdown at ten")
	var saved := Save.encode(state)
	Damage.hurt(state, state.x + 10 * S)
	check(Save.encode(state) == saved, "Flashing rejects a second damage request without mutation")
	state.enemies[0].status = 3  # Isolate the timer from a knockback-to-stomp bounce.
	for tick in Life.COUNTDOWN_STEPS - 1:
		Sim.advance(state, Sim.RIGHT, test_world)
	check(
		state.health == 10 and state.hits == 1, "Countdown waits 46 ticks without another contact"
	)
	Sim.advance(state, 0, test_world)
	check(state.health == 9, "Countdown decrements at 0.75 seconds")
	state.x = state.recovery_x
	state.y = state.recovery_y + S
	state.vx = 0
	state.vy = 0
	Sim.advance(state, 0, test_world)
	check(
		state.life_phase == Life.REJOIN and state.health == 9,
		"Bubble contact starts the rejoin phase"
	)
	for tick in Life.REJOIN_STEPS:
		Sim.advance(state, 0, test_world)
	check(
		state.separated == 0 and state.life_phase == Life.PLAY,
		"Rejoin completes after fifty-one ticks"
	)
	state.x = 200 * S  # Refill is isolated from a second enemy contact.
	for tick in 120:
		Sim.advance(state, 0, test_world)
	check(state.health == 10, "Recovery refills one per two seconds to ten")
	var restored := Save.decode(saved, test_world.identity)
	check(restored.ok, "Hurt and generator state decode")
	var timer_state: Dictionary = restored.state.duplicate(true)
	var timer_world := test_world.duplicate(true)
	timer_world.enemies.clear()
	timer_state.enemies.clear()
	for tick in Life.IMMUNITY - 1:
		Sim.advance(timer_state, 0, timer_world)
	check(
		timer_state.invulnerable == 1 and timer_state.hurt == 0,
		"Hurt ends before the full two-second immunity window"
	)
	Sim.advance(timer_state, 0, timer_world)
	check(timer_state.invulnerable == 0, "Invulnerability ends after 121 ticks")
	state = restored.state
	state.enemies[0].status = 3
	state.x = 1000 * S  # Remain on support, away from the marker; this must not be a pit death.
	for tick in 1200:
		Sim.advance(state, 0, test_world)
		if state.deaths and state.life_phase == Life.PLAY:
			break
	check(
		state.deaths == 1 and state.health == 10,
		"Unrecovered countdown completes capture, death and respawn"
	)
	check(
		state.enemies[0].status == 1, "Countdown reset activates actors from the fresh spawn camera"
	)
	var old := saved.duplicate()
	old.encode_u32(8, 2)
	check(Save.decode(old, world.identity).get("error") == "Snapshot format/version", "v2 rejected")
	check(not Save.decode(saved.slice(0, -1), world.identity).ok, "New state truncation rejected")


func leap_and_capture_checks(world: Dictionary) -> void:
	var fish_world := fixture(world, "e20")
	fish_world.enemies[0].variant = 1
	var fish := _placed_state(fish_world)
	var leaped := false
	var floated := false
	for tick in 720:
		Sim.advance(fish, 0, fish_world)
		leaped = leaped or fish.enemies[0].vy == -944 * 60
		floated = floated or fish.enemies[0].water == 1
	check(leaped and floated, "Vertical fish floats, waits, prepares and leaps at configured speed")
	patrol_order_checks(world)
	var plant_world := fixture(world, "e5")
	var player := _placed_state(plant_world)
	player.x = 430 * S
	player.y = 290 * S
	for tick in 20:
		Sim.advance(player, 0, plant_world)
	check(player.captured_by == 1, "Unfrozen plant head captures from above")
	var emptied := player.duplicate(true)
	emptied.health = 0
	var summoned := false
	for tick in 60:
		Sim.advance(emptied, 0, plant_world)
		if emptied.separated:
			summoned = emptied.rescue_active == 1
			break
	check(summoned, "A plant capture at zero summons the captors in the separating step")
	var captor: Dictionary = player.enemies[0]
	check(captor.head_size == 15, "Head growth continues to native size during capture")
	check(
		captor.pin_size > 0 and captor.pin_size < 15,
		"Capture-time scale stays separate from continuing growth"
	)
	var bad_pin := player.duplicate(true)
	bad_pin.entities[0].pin_size = 16
	check(
		not Save.decode(Save.encode(bad_pin), plant_world.identity).ok,
		"Snapshot rejects an invalid pin scale"
	)
	var reach: int = 44 * (16 * S + 48 * S * captor.pin_size / 15) / 64
	check(
		(
			player.x == captor.x + captor.facing * 2 * S + reach * captor.head_dx / S
			and player.y == captor.y - 10 * S + reach * captor.head_dy / S
		),
		"Capture pins the player to the head anchor, not the stem pivot"
	)
	var restored := Save.decode(Save.encode(player), plant_world.identity)
	check(restored.ok and restored.state == player, "Capture hold and head geometry save exactly")
	var escaped_at := 0
	for tick in 220:
		Sim.advance(player, 4 if tick % 2 == 0 else 0, plant_world)
		Sim.advance(restored.state, 4 if tick % 2 == 0 else 0, plant_world)
		if player.captured_by == 0:
			escaped_at = tick
			break
	check(escaped_at > 30 and escaped_at < 150, "Jump presses shorten hold only after flee delay")
	check(
		player.invulnerable == Life.IMMUNITY and player.hurt_deceleration == 648,
		"Plant release flashes with release deceleration"
	)
	check(
		player.hurt == Life.KNOCKED_LOCK and player.hurt_phase == Life.HURT_KNOCKED,
		"Plant release starts the knock-back lock"
	)
	check(
		Save.encode(player) == Save.encode(restored.state),
		"Capture and escape future matches restore"
	)


func lifecycle_checks(world: Dictionary) -> void:
	var test_world := fixture(world, "e2")
	# Wide enough that the map-clamped screen can move 832 px away from the actor.
	test_world.width = 4096 * S
	test_world.maps[1].width = test_world.width
	var player := _placed_state(test_world)
	Sim.advance(player, 0, test_world)
	check(player.enemies[0].status == 1, "Enemy activates in reference view")
	player.x = 2000 * S
	player.camera_x = player.x
	Sim.advance(player, 0, test_world)
	check(
		player.enemies[0].status == 2 and player.enemies[0].offscreen == 1,
		"Alive actor queues offscreen respawn"
	)
	player.x = 200 * S
	player.camera_x = player.x
	# The recreated actor wakes in this step and first moves in the next.
	Sim.advance(player, 0, test_world)
	Sim.advance(player, 0, test_world)
	check(
		player.enemies[0].status == 1 and player.enemies[0].phase == 360,
		"Returning recreates the placement, not a timer"
	)
	player.enemies[0].status = 3
	player.x = 2000 * S
	player.camera_x = player.x
	Sim.advance(player, 0, test_world)
	player.x = 200 * S
	player.camera_x = player.x
	Sim.advance(player, 0, test_world)
	check(player.enemies[0].status == 3, "Defeat does not request automatic respawn")
	player.invulnerable = 120
	player.y = test_world.height + 100 * S
	Sim.advance(player, 0, test_world)
	check(
		player.deaths == 1 and player.life_phase == Life.DEAD,
		"Pit starts the death phase even while invulnerable"
	)
	player.life_phase = Life.RESPAWN
	Sim.advance(player, 0, test_world)
	check(
		player.life_phase == Life.FADE_IN and player.enemies[0].status == Registry.WAITING,
		"Respawn recreates defeated actors before fade-in"
	)


func boundary_checks(code: String) -> void:
	var original: Dictionary = JSON.parse_string(code)
	for value: Variant in ["1", [], -1, 0.5]:
		var source := original.duplicate(true)
		source.maps.map1.objects["3"].M = value
		check(
			not World.build(JSON.stringify(source), Collision.read()).ok,
			"Enemy mirror rejects invalid value %s" % str(value)
		)
	var source := original.duplicate(true)
	source.maps.map1.objects["3"].M = 7
	var degraded: Dictionary = World.build(JSON.stringify(source), Collision.read())
	check(
		(
			degraded.ok
			and degraded.world.entities.any(
				func(placed: Dictionary) -> bool: return placed.id == "3" and placed.code == "?e5"
			)
			and degraded.world.enemies.size() == 4
		),
		"An unbuilt mirror mode becomes a placeholder, not a guessed plant"
	)
	var real_world: Dictionary = World.build(code, Collision.read()).world
	var player := _placed_state(real_world)
	var bytes := Save.encode(player)
	check(
		bytes.size() > Save.minimum_size() and bytes.decode_u32(8) == 10,
		"Composed v10 snapshot includes the entity table"
	)
	player.health = 0
	check(
		Save.decode(Save.encode(player), real_world.identity).ok,
		"Zero countdown remains valid while attached"
	)
	player = _placed_state(real_world)
	player.separated = 1
	check(
		not Save.decode(Save.encode(player), real_world.identity).ok,
		"A separated companion cannot restore in attached mode"
	)
	player = _placed_state(real_world)
	player.enemies[0].status = 4
	check(
		not Save.decode(Save.encode(player), real_world.identity).ok,
		"Invalid enemy lifecycle rejected"
	)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


## Entities run one world tick at level start, as in the original. These unit checks
## start from the placement, so the table is spawned again after the level start.
## Platform order for a patrolling fish: it moves by the mean of its old and new speed
## while it speeds up, and a turn first coasts one tick and then brakes by its old speed.
func patrol_order_checks(world: Dictionary) -> void:
	var fish_world := fixture(world, "e20")
	fish_world.enemies[0].variant = 0
	var state := _placed_state(fish_world)
	var fish: Dictionary = state.enemies[0]
	var moves: Array[int] = []
	var turn_moves: Array[int] = []
	var turn_at := -1
	for tick in 120:
		var before: int = fish.x
		var mode: int = fish.mode
		Sim.advance(state, 0, fish_world)
		if fish.water and mode == 0 and fish.mode == 0:
			moves.append(absi(fish.x - before))
		if mode == 1 and turn_moves.size() < 3:
			turn_moves.append(absi(fish.x - before))
		var crossed: bool = (
			(fish.facing < 0 and fish.x < fish.home_x - fish.fish_left)
			or (fish.facing > 0 and fish.x > fish.home_x + fish.fish_right)
		)
		if mode == 0 and crossed and turn_at < 0:
			turn_at = tick if fish.mode == 1 else tick + 1000
	var speeding := moves.filter(func(move: int) -> bool: return move > 0 and move < 7680)
	check(
		(
			speeding.size() > 2
			and speeding.all(func(move: int) -> bool: return move % 512 == 256)
			and speeding[1] - speeding[0] == 512
		),
		"A patrolling fish speeds up by the mean of its old and new speed"
	)
	check(
		turn_at >= 0 and turn_at < 1000,
		"A fish turn starts on the step whose move crosses the patrol limit"
	)
	check(
		turn_moves == [7680, 7680, 7168],
		"A fish turn coasts one tick at full speed, then brakes by its old speed"
	)


func _placed_state(world: Dictionary) -> Dictionary:
	var state := State.create(world)
	Registry.spawn_map(state, world)
	return state
