extends SceneTree
## Synthetic checks of the original's platform step order (gravity, landing, flutter,
## facing, walls, map edges, stomps). Uses the moves test fixtures; no game scene.
const Moves = preload("res://src/sim/moves.gd")
const Flutter = preload("res://src/sim/move_flutter.gd")
const Bits = preload("res://src/sim/move_input.gd")
const Sim = preload("res://src/sim/step.gd")
const Fixture = preload("res://tests/moves.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	platform_order_checks()
	print("MOVE_ORDER_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Step-order rules shared with the original's platform movement.
func platform_order_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	state.x = (1024 + 11) * S
	state.vx = 400 * 60
	tick(state, Bits.RIGHT, world)
	check(
		state.on_floor == 0 and state.vy == 0,
		"walking off a ledge adds no gravity on the step that leaves the floor"
	)
	var y: int = state.y
	tick(state, Bits.RIGHT, world)
	check(state.vy == Moves.GRAVITY and state.y == y, "the fall starts on the next step")
	state = actor(world)
	tick(state, 0, world)
	y = state.y
	state.vy = -384 * 60  # A ground knockback, as a damage contact sets it.
	tick(state, 0, world)
	check(
		state.vy == -384 * 60 and state.y == y - 384 * 60 + Moves.GRAVITY / 2,
		"a knockback from the floor keeps its speed for one step"
	)
	tick(state, 0, world)
	check(state.vy == -384 * 60 + Moves.GRAVITY, "gravity starts once the body is airborne")
	world = empty_world()
	state = actor(world)
	state.previous_input = Bits.JUMP
	state.vy = 200 * 60
	tick(state, Bits.JUMP, world)
	var damped: int = state.vy
	check(state.flutter_remaining == Flutter.TICKS - 1, "held jump starts the flutter")
	tick(state, 0, world)
	var expected := damped + (-264 * 60 - damped) * 37649 / 1000000 + Moves.GRAVITY
	check(
		state.vy == expected and state.flutter_remaining == 0,
		"releasing jump damps the flutter once more before it ends"
	)
	check(state.flutter_cooldown == Flutter.COOLDOWN, "the release starts the delay")
	var started := -1
	for count in 20:
		tick(state, Bits.JUMP, world)
		if started < 0 and state.flutter_remaining:
			started = count + 1
	check(started == Flutter.COOLDOWN, "the next flutter starts 17 steps after a cancel")
	state = actor(world)
	state.previous_input = Bits.JUMP
	state.vy = 200 * 60
	for count in Flutter.TICKS:
		tick(state, Bits.JUMP, world)
	check(
		state.flutter_remaining == 0 and state.move_gravity_tick == 2,
		"the lift damps on 41 steps; its last step falls with full gravity"
	)
	var before: int = state.vy
	tick(state, Bits.JUMP, world)
	check(state.vy - before == 1080, "then gravity recovers along the source ease-out curve")
	state = actor(world)
	state.previous_input = Bits.JUMP
	state.vy = 300 * 60
	tick(state, Bits.JUMP, world)
	check(state.flutter_remaining > 0, "the flutter runs before the stomp")
	Moves.bounce(state, -320 * 60, Bits.JUMP)  # An enemy contact after the move.
	tick(state, Bits.JUMP, world)
	var bounced: int = state.vy
	check(
		bounced == -704 * 60 + Moves.GRAVITY and state.flutter_remaining > 0,
		"after a stomp the flutter lasts one more move under normal gravity"
	)
	tick(state, Bits.JUMP, world)
	check(
		(
			state.vy == bounced + (-424 * 60 - bounced) * 37649 / 1000000 + Moves.GRAVITY
			and state.flutter_remaining == 0
		),
		"then it damps once more toward the boosted target and ends"
	)
	var roofed := empty_world()
	var roof := []
	for column in 32:
		roof.append([column, 4])
	roofed.layers.append(layer("terrain", true, false, roof))
	state = actor(roofed)
	state.y = 220 * S
	state.vy = -100 * 60
	state.previous_input = Bits.JUMP
	state.flutter_remaining = 20
	state.flutter_ready = 0
	for count in 8:
		tick(state, Bits.JUMP, roofed)
	check(
		state.move_action == Moves.NORMAL and state.flutter_remaining > 0 and state.y < 220 * S,
		"a flutter that rises into a ceiling does not start the head bump pose"
	)
	state = actor(world)
	state.previous_input = Bits.JUMP
	state.move_action = Moves.HEAD_BUMP
	state.vy = 200 * 60
	tick(state, Bits.JUMP, world)
	check(
		state.flutter_remaining > 0 and state.move_action == Moves.NORMAL,
		"a flutter may start during the head bump pose and replaces it"
	)
	world = floor_world()
	state = actor(world)
	state.y = 254 * S
	state.vx = 300 * 60
	state.vy = 200 * 60
	state.previous_input = Bits.JUMP
	state.flutter_remaining = 10
	state.flutter_ready = 0
	tick(state, Bits.JUMP, world)
	var landed: int = state.y
	check(
		state.on_floor == 1 and state.flutter_remaining > 0 and state.movement != 6,
		"a flutter that lands ends on the next step and shows the ground pose"
	)
	tick(state, Bits.JUMP, world)
	check(
		(
			state.y == landed - Flutter.LANDING_LIFT
			and state.vy == Moves.GRAVITY
			and state.on_floor == 0
			and state.flutter_remaining == 0
			and state.flutter_cooldown == Flutter.COOLDOWN
			and state.vx == 256 * 60 - 1296
		),
		"the landing step clamps vx, ends the flutter and lifts the body 2 px"
	)
	for count in 4:
		tick(state, Bits.JUMP, world)
	check(state.on_floor == 1 and absi(state.y - landed) <= S / 8, "the lifted body lands again")
	state = actor(world)
	state.y = 255 * S
	state.vy = 100 * 60
	tick(state, Bits.JUMP, world)
	check(
		state.vy == -Moves.JUMP_SPEED and state.move_jump_carry == 1,
		"a buffered jump starts when the fall settles on the floor"
	)
	tick(state, Bits.JUMP, world)
	check(
		state.vy == -Moves.JUMP_SPEED + Moves.GRAVITY,
		"the next move still counts that jump and adds gravity"
	)
	state = actor(world)
	state.y = 255 * S
	state.vx = 300 * 60
	state.vy = 100 * 60
	state.flutter_remaining = 10
	state.flutter_ready = 0
	tick(state, Bits.JUMP | Bits.RIGHT, world)
	tick(state, Bits.JUMP | Bits.RIGHT, world)
	check(
		(
			state.flutter_remaining == 0
			and state.vy == -Moves.JUMP_SPEED + Moves.GRAVITY
			and state.vx == 256 * 60 + 512
		),
		"a jump during a flutter keeps that step's vx clamp, then ends the flutter"
	)
	state = actor(world)
	state.x = 20 * S
	for count in 40:
		tick(state, Bits.LEFT, world)
	check(
		state.vx == 0 and state.x > 12 * S and state.x < 13 * S and state.move_push == 1,
		"the map side edge stops the player like a wall"
	)
	state = actor(world)
	state.on_floor = 1
	state.vy = 300 * 60
	check(Moves.pit_height(state) == 62 * S, "grounded poses keep the fixed pit height")
	state.on_floor = 0
	check(Moves.pit_height(state) == 66 * S, "a falling player uses the fall pose height")
	state.flutter_remaining = 5
	check(Moves.pit_height(state) == 68 * S, "a fluttering player uses the flutter pose height")
	state.flutter_remaining = 0
	state.move_held_id = 7
	check(Moves.pit_height(state) == 64 * S, "a full mouth uses the full fall pose height")


func tick(state: Dictionary, input: int, world: Dictionary) -> void:
	Sim.advance(state, input, world)
	check(Moves.valid_state(state), "step produces valid integer player state")


static func actor(world: Dictionary) -> Dictionary:
	return Fixture.actor(world)


static func empty_world() -> Dictionary:
	return Fixture.empty_world()


static func floor_world() -> Dictionary:
	return Fixture.floor_world()


static func layer(name: String, solid: bool, water: bool, filled: Array) -> Dictionary:
	return Fixture.layer(name, solid, water, filled)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
