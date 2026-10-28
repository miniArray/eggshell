extends SceneTree
## Synthetic fixed-step player checks. No game scene, rendering or recordings.
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Moves = preload("res://src/sim/moves.gd")
const Bits = preload("res://src/sim/move_input.gd")
const Water = preload("res://src/sim/water.gd")
const World = preload("res://src/sim/world.gd")
const Pose = preload("res://src/view/player_pose.gd")
const S := 3600
const GAP := S / 16
var checks := 0
var failures := 0


func _initialize() -> void:
	motion_checks()
	posture_checks()
	pound_checks()
	tongue_checks()
	food_checks()
	aim_checks()
	ammo_checks()
	request_checks()
	water_checks()
	schema_checks()
	pose_checks()
	print("MOVES_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func motion_checks() -> void:
	var world := empty_world()
	var state := actor(world)
	for count in 100:
		tick(state, Bits.RIGHT, world)
	check(state.vx == 400 * 60, "direction input reaches running speed without a modifier")
	state = actor(world)
	state.vx = 100 * 60
	tick(state, 0, world)
	check(state.vx == 100 * 60, "releasing direction preserves ordinary airborne momentum")
	tick(state, Bits.LEFT | Bits.RIGHT, world)
	check(state.vx == 100 * 60 - 1296, "opposite directions brake in the air")
	state = actor(world)
	var x: int = state.x
	tick(state, Bits.RIGHT, world)
	check(state.x == x and state.vx == 512, "first acceleration tick does not translate rest")
	tick(state, Bits.RIGHT, world)
	check(state.x == x + 768, "translation includes half the horizontal acceleration")
	world = floor_world()
	state = actor(world)
	state.vx = 400 * 60
	tick(state, Bits.LEFT, world)
	check(state.vx == 400 * 60 - 1808 and state.move_turn == -1, "ground reversal adds braking")
	for count in 13:
		tick(state, Bits.LEFT, world)
	check(state.vx <= -96 * 60 and state.facing == -1, "turn exit supplies the direction impulse")
	state = actor(world)
	var y: int = state.y
	tick(state, Bits.JUMP, world)
	check(state.y == y - Moves.JUMP_SPEED + 1024, "jump uses half-gravity displacement")
	var vy: int = state.vy
	tick(state, 0, world)
	check(state.vy == vy / 4 + Moves.GRAVITY, "release cuts the upward velocity once")
	state = actor(world)
	var fluttered := false
	for count in 70:
		tick(state, Bits.JUMP, world)
		fluttered = fluttered or state.flutter_remaining > 0
	check(fluttered, "holding the ground jump continues into the first flutter")
	world = empty_world()
	state = actor(world)
	state.vy = 200 * 60
	tick(state, Bits.JUMP, world)
	check(state.flutter_remaining == 39, "ordinary flutter starts a forty-tick lift")
	Moves.set_waterfall_contact(state, true)
	tick(state, Bits.JUMP, world)
	check(state.flutter_remaining == 59, "flow contact extends the remaining lift")
	Moves.set_waterfall_contact(state, false)
	tick(state, Bits.JUMP, world)
	check(state.flutter_remaining == 37, "leaving flow removes its extension")
	for count in 37:
		tick(state, Bits.JUMP, world)
	check(state.move_gravity_tick > 0, "lift expiration starts gradual gravity recovery")
	var checkpoint := state.duplicate(true)
	for count in 25:
		tick(state, Bits.JUMP, world)
		tick(checkpoint, Bits.JUMP, world)
	check(
		state == checkpoint and state.move_gravity_tick == 0,
		"gravity recovery has a saved exact future"
	)


func posture_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	state.vx = 100 * 60
	tick(state, Bits.DOWN, world)
	check(
		state.move_duck == 1 and state.vx == 0 and Moves.player_box(state)[1] == -52 * S,
		"duck starts with its first collider and stops motion"
	)
	for count in 5:
		tick(state, Bits.DOWN, world)
	check(Moves.player_box(state)[1] == -32 * S, "duck reaches the low collider after its entry")
	var roof := layer("roof", true, false, [[4, 6]], [0, 0, 1, 0, 1, 0.5, 0, 0.5])
	world.layers.append(roof)
	tick(state, 0, world)
	check(
		state.move_duck == 1 and state.y == world.spawn_y, "release cannot expand into a low roof"
	)
	tick(state, Bits.JUMP, world)
	check(state.on_floor == 1, "low roof blocks standing jump without moving through it")
	world.layers.pop_back()
	tick(state, Bits.JUMP, world)
	check(state.vy < 0 and state.move_duck == 0, "buffered jump can expand when the roof clears")
	state = actor(world)
	tick(state, Bits.UP, world)
	check(state.move_look == 1, "stationary grounded up input looks up")
	tick(state, 0, world)
	check(state.move_look == 0, "look ends on release")
	world.layers.append(layer("wall", true, false, [[5, 6], [5, 7]]))
	state = actor(world)
	state.x = 148 * S - GAP
	tick(state, Bits.RIGHT, world)
	check(state.move_push == 1 and state.vx == 0, "wall contact selects push without velocity")
	world = floor_world()
	state = actor(world)
	state.vx = 400 * 60
	tick(state, Bits.LEFT, world)
	tick(state, Bits.LEFT | Bits.DOWN, world)
	check(state.move_duck == 0 and state.move_turn == -1, "turn action delays the duck posture")


func pound_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	state.y = 100 * S
	var y: int = state.y
	tick(state, Bits.DOWN, world)
	check(
		state.move_action == Moves.POUND_START and state.vy == 0, "air down starts a stopped windup"
	)
	for count in 23:
		tick(state, Bits.DOWN | Bits.RIGHT, world)
	check(state.y == y and state.vx == 0, "windup holds both axes for twenty-four ticks")
	tick(state, Bits.DOWN, world)
	check(
		state.move_action == Moves.POUND_FALL and state.vy == 1408 * 60,
		"pound switches to twice the fall cap"
	)
	for count in 20:
		tick(state, Bits.DOWN, world)
	check(
		state.move_action == Moves.POUND_LAND and state.move_impact == 1,
		"one landing publishes one impact"
	)
	var impact := Moves.impact_request(state)
	check(
		impact.serial == 1 and impact.y == state.y,
		"impact location is latched for object consumers"
	)
	tick(state, 0, world)
	check(
		state.move_action == Moves.NORMAL and state.move_pound_delay == 6,
		"release exits landing with a re-entry delay"
	)
	state = actor(world)
	tick(state, Bits.DOWN | Bits.JUMP, world)
	check(
		state.move_action != Moves.POUND_START and state.move_pound_delay == 6,
		"ground jump has pound protection"
	)
	state.move_action = Moves.POUND_FALL
	check(Moves.bounce(state, -320 * 60, Bits.JUMP), "object consumers can supply a bounce")
	check(
		(
			state.vy == -704 * 60
			and state.move_action == Moves.NORMAL
			and state.boosted_flutter == 1
			and state.flutter_ready == 1
		),
		"bounce adds held-jump lift and cancels pound physics"
	)
	check(not Moves.bounce(state, 0, 0), "bounce rejects a non-upward velocity")
	check(
		not Moves.bounce(state, -9223372036854775807, Bits.JUMP),
		"bounce rejects an overflowing held-jump adjustment"
	)
	var priority := actor(world)
	priority.y = 100 * S
	tick(priority, Bits.DOWN | Bits.USE | Bits.THROW, world)
	check(
		priority.move_action == Moves.POUND_START and Moves.tongue_box(priority).is_empty(),
		"air pound takes precedence over new tongue and aim input"
	)
	world = empty_world()
	state.vy = 200 * 60
	tick(state, Bits.JUMP, world)
	check(state.flutter_remaining == 49, "bounce permits the extended flutter")


func tongue_checks() -> void:
	var world := empty_world()
	var state := actor(world)
	check(Moves.tongue_box(state).is_empty(), "inactive tongue has no sensor")
	var priority := actor(world)
	tick(priority, Bits.USE | Bits.THROW, world)
	check(priority.move_action == Moves.TONGUE, "new tongue input precedes new aim input")
	tick(state, Bits.USE, world)
	check(state.move_action == Moves.TONGUE, "use starts the forward tongue action")
	check(
		Moves.tongue_box(state) == [state.x, state.y - 31 * S, state.x + 48 * S, state.y - 17 * S],
		"initial right sensor has its trailing rectangle"
	)
	tick(state, Bits.USE, world)
	check(
		state.move_tongue_length == 16 * S + 112 * S / 6,
		"sensor extension retains fractional pixels"
	)
	for count in 5:
		tick(state, Bits.USE, world)
	check(state.move_tongue_length == 128 * S, "tongue reaches its full forward extent")
	check(
		(
			Moves.tongue_box(state)
			== [state.x + 112 * S, state.y - 31 * S, state.x + 160 * S, state.y - 17 * S]
		),
		"full right sensor follows its tip"
	)
	var saved := state.duplicate(true)
	Moves.tongue_box(state)
	check(state == saved, "tongue sensor query is read-only")
	for count in 6:
		tick(state, Bits.USE, world)
	check(
		state.move_action != Moves.TONGUE and Moves.tongue_box(state).is_empty(),
		"tongue retracts without repeating held use"
	)
	state = actor(world)
	state.facing = -1
	tick(state, Bits.USE, world)
	for count in 6:
		tick(state, Bits.USE, world)
	check(
		(
			Moves.tongue_box(state)
			== [state.x - 160 * S, state.y - 31 * S, state.x - 112 * S, state.y - 17 * S]
		),
		"left sensor mirrors its unequal tip margins"
	)
	state = actor(world)
	tick(state, Bits.UP | Bits.USE, world)
	for count in 6:
		tick(state, Bits.UP | Bits.USE, world)
	check(
		(
			state.move_tongue_length == 120 * S
			and (
				Moves.tongue_box(state)
				== [state.x + 7 * S, state.y - 162 * S, state.x + 21 * S, state.y - 114 * S]
			)
		),
		"up sensor has its vertical shape and origin"
	)
	world = water_world()
	state = actor(world)
	state.swimming = 1
	state.y = 352 * S
	tick(state, Bits.UP | Bits.USE, world)
	check(
		(
			Moves.tongue_box(state)
			== [state.x - 3 * S, state.y - 58 * S, state.x + 11 * S, state.y - 10 * S]
		),
		"swimming up sensor uses the water origin"
	)
	state = actor(world)
	state.swimming = 1
	state.y = 352 * S
	tick(state, Bits.UP | Bits.USE | Bits.JUMP, world)
	for count in 3:
		tick(state, Bits.UP | Bits.USE | Bits.JUMP, world)
	check(
		(
			not state.swimming
			and Moves.tongue_box(state)[0] == state.x - 3 * S
			and Pose.select(state).name == "TongueUp1"
		),
		"tongue keeps its selected water origin after leaving water"
	)
	world = water_world()
	world.layers.append(layer("side", true, false, [[4, 9]], [0.5625, 0, 1, 0, 1, 1, 0.5625, 1]))
	state = actor(world)
	state.swimming = 1
	state.y = 352 * S
	tick(state, Bits.UP | Bits.USE, world)
	check(state.move_tongue_phase == Moves.TONGUE_FAILED, "water mouth probe can also fail")
	for count in 3:
		tick(state, Bits.UP | Bits.USE, world)
	check(state.move_action != Moves.TONGUE, "one-frame wet failure finishes in three ticks")
	world = floor_world()
	world.layers.append(layer("wall", true, false, [[5, 6], [5, 7]]))
	state = actor(world)
	tick(state, Bits.USE, world)
	check(
		state.move_tongue_phase == Moves.TONGUE_FAILED and Moves.tongue_box(state).is_empty(),
		"blocked mouth never creates a sensor"
	)
	for count in 5:
		tick(state, 0, world)
	check(state.move_action != Moves.TONGUE, "blocked mouth finishes its short action")
	world = floor_world()
	world.layers.append(layer("wall", true, false, [[6, 6], [6, 7]]))
	state = actor(world)
	tick(state, Bits.USE, world)
	for count in 6:
		tick(state, Bits.USE, world)
	check(
		state.move_tongue_phase == Moves.TONGUE_BLOCKED and Moves.tongue_box(state)[2] < 192 * S,
		"outgoing sensor stops at a distant solid wall"
	)
	for count in 24:
		tick(state, 0, world)
	check(state.move_action != Moves.TONGUE, "blocked tongue also returns")


func food_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	tick(state, Bits.USE, world)
	check(Moves.catch_item(state, 42), "object consumer can attach a digestible item")
	check(Moves.tongue_box(state).is_empty(), "a caught item disables a second tongue contact")
	tick(state, Bits.DOWN, world)
	check(state.move_swallow_queue == 1, "down queues eating during return")
	for count in 11:
		tick(state, Bits.DOWN, world)
	check(
		state.move_action == Moves.LAY and state.move_digest_ticks == 18,
		"return begins queued eating"
	)
	check(
		Moves.spawn_request(state).kind == Moves.REQUEST_CONSUME,
		"eating emits a stable consume request"
	)
	for count in 18:
		tick(state, 0, world)
	check(
		state.move_eggs == 1 and Moves.spawn_request(state).kind == Moves.REQUEST_STORED_EGG,
		"eating produces inventory after its delay"
	)
	Moves.give_eggs(state, 9223372036854775807)
	check(state.move_eggs == 6, "inventory cap is safe even for a large grant")
	state = actor(world)
	tick(state, Bits.USE, world)
	check(Moves.catch_item(state, 43, 0), "non-digestible items can also be held")
	for count in 12:
		tick(state, 0, world)
	tick(state, Bits.UP | Bits.USE, world)
	var request := Moves.spawn_request(state)
	check(
		(
			request.kind == Moves.REQUEST_SPIT
			and request.item == 43
			and request.vx == 0
			and request.vy == -768 * 60
			and state.move_held_id == 0
		),
		"up use releases the held item through its object hook"
	)
	state = actor(world)
	tick(state, Bits.USE, world)
	Moves.catch_item(state, 44)
	for count in 12:
		tick(state, 0, world)
	Moves.give_eggs(state, 1)
	tick(state, Bits.DOWN, world)
	tick(state, Bits.THROW, world)
	for count in 17:
		tick(state, 0, world)
	check(state.move_eggs == 2, "aiming does not erase an in-flight digestion timer")
	check(not Moves.catch_item(state, 99), "catch hook rejects contacts outside the tongue action")
	state = actor(world)
	tick(state, Bits.DOWN | Bits.USE, world)
	Moves.catch_item(state, 45)
	for count in 12:
		tick(state, Bits.DOWN, world)
	check(state.move_action == Moves.LAY, "down on the tongue start tick also queues eating")


func aim_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	Moves.give_eggs(state, 2)
	tick(state, Bits.THROW, world)
	check(
		state.move_aim == 1 and state.move_eggs == 2,
		"first throw press aims without consuming inventory"
	)
	tick(state, 0, world)
	check(state.move_aim_angle == 42750, "aim sweeps at the fixed angle rate")
	tick(state, Bits.LOCK, world)
	var angle: int = state.move_aim_angle
	for count in 5:
		tick(state, 0, world)
	check(state.move_aim_angle == angle, "lock toggles a paused aim")
	tick(state, Bits.UP, world)
	check(state.move_aim_angle == -90000, "up selects vertical aim")
	tick(state, Bits.THROW, world)
	var request := Moves.spawn_request(state)
	check(
		(
			request.kind == Moves.REQUEST_EGG
			and request.angle == -90000
			and state.move_eggs == 1
			and state.move_aim == 0
		),
		"second throw press publishes an aimed request"
	)
	for count in 14:
		tick(state, 0, world)
	tick(state, Bits.THROW, world)
	tick(state, Bits.USE, world)
	check(
		state.move_aim == 0 and state.move_action != Moves.TONGUE and state.move_eggs == 1,
		"use cancels aim without also attacking"
	)
	state = actor(world)
	tick(state, Bits.THROW, world)
	check(
		state.move_aim == 0 and Moves.spawn_request(state).is_empty(),
		"empty inventory never publishes a projectile"
	)


func ammo_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	tick(state, Bits.USE, world)
	check(
		Moves.catch_item(state, 7, 0, Moves.SEED, 60, 1),
		"ammo hook accepts the largest supported seed supply"
	)
	check(
		Moves.spawn_request(state).is_empty(),
		"ammo item waits for tongue return before consumption"
	)
	for count in 12:
		tick(state, 0, world)
	tick(state, Bits.USE, world)
	check(state.move_ammo_count == 60, "first seed waits for the short emission pose")
	for count in 4:
		tick(state, Bits.USE, world)
	check(
		state.move_ammo_count == 59 and Moves.spawn_request(state).kind == Moves.REQUEST_SEED,
		"held use emits one seed each four ticks"
	)
	var checkpoint := state.duplicate(true)
	for count in 20:
		tick(state, Bits.USE, world)
		tick(checkpoint, Bits.USE, world)
	check(state == checkpoint, "seed spread and request sequence have a saved deterministic future")
	for count in 4:
		tick(state, 0, world)
	check(
		state.move_action == Moves.NORMAL and state.move_spread == 0,
		"release stops the seed loop and clears spread"
	)
	state = actor(world)
	tick(state, Bits.USE, world)
	Moves.catch_item(state, 8, 0, Moves.HEAT, 3, 1)
	for count in 12:
		tick(state, 0, world)
	tick(state, Bits.UP | Bits.USE, world)
	check(
		(
			Moves.spawn_request(state).kind == Moves.REQUEST_HEAT
			and state.move_ammo_count == 2
			and state.move_emit_angle == -90000
		),
		"charged up use emits one heat request"
	)
	for count in 30:
		tick(state, Bits.USE, world)
	check(state.move_ammo_count == 2, "holding use does not repeat charged emissions")


func request_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	Moves.give_eggs(state, 2)
	state.move_aim = 1
	state.move_digest_ticks = 1
	tick(state, Bits.THROW, world)
	var result := Moves.spawn_requests(state, 0)
	check(
		(
			result.ok
			and result.requests.size() == 2
			and result.requests[0].kind == Moves.REQUEST_STORED_EGG
			and result.requests[1].kind == Moves.REQUEST_EGG
		),
		"digestion and throw retain both requests in order"
	)
	var checkpoint := state.duplicate(true)
	check(
		Moves.spawn_requests(checkpoint, 0) == result,
		"pending request history belongs to saved player fields"
	)
	check(
		(
			Moves.spawn_requests(state, 1).requests.size() == 1
			and Moves.spawn_requests(state, 2).requests.is_empty()
		),
		"request cursor prevents repeated consumption"
	)
	for count in 3:
		state.move_digest_ticks = 1
		tick(state, 0, world)
	check(not Moves.spawn_requests(state, 0).ok, "stale request cursor fails explicitly")
	check(
		Moves.spawn_requests(state, 1).requests.size() == 4,
		"recent request history remains available"
	)
	check(not Moves.spawn_requests(state, -1).ok, "negative request cursor is rejected")
	Moves.reset(state)
	check(
		(
			Moves.spawn_requests(state, 0).requests.is_empty()
			and not Moves.spawn_requests(state, 5).ok
		),
		"reset clears requests and detects an old cursor"
	)
	state = actor(world)
	tick(state, Bits.USE, world)
	Moves.catch_item(state, 101, 0)
	for count in 12:
		tick(state, 0, world)
	tick(state, Bits.UP | Bits.USE, world)
	state.move_digest_ticks = 1
	tick(state, 0, world)
	result = Moves.spawn_requests(state, 0)
	check(
		result.ok and result.requests[0].vy == -768 * 60 and result.requests[0].item == 101,
		"request history retains the spit velocity and item"
	)


func water_checks() -> void:
	check(
		(
			Water.bob_position(15) == 3 * S
			and Water.bob_position(30) == 4 * S
			and Water.bob_position(60) == 0
		),
		"water bob follows a closed eased path"
	)
	var world := water_world()
	var state := actor(world)
	state.y = 400 * S
	for count in 16:
		tick(state, 0, world)
	check(state.swimming == 1 and state.vy < 0, "deep water enters with a delayed lift")
	check(state.hurt_deceleration == 128, "water entry selects the liquid braking value")
	state.hurt_deceleration = 648
	state.vx = 100 * 60
	tick(state, 0, world)
	check(
		state.hurt_deceleration == 648 and state.vx == 100 * 60 - 648,
		"water preserves and uses a later braking override"
	)
	state.y = 100 * S
	tick(state, 0, world)
	check(
		not state.swimming and state.hurt_deceleration == 1296,
		"water exit restores ordinary braking"
	)
	state.hurt_deceleration = 648
	tick(state, 0, world)
	check(state.hurt_deceleration == 648, "dry frames do not overwrite another braking value")
	state = actor(world)
	state.y = 400 * S
	state.frame = 10
	state.previous_input = Bits.JUMP
	state.flutter_remaining = 20
	tick(state, Bits.JUMP, world)
	check(
		state.flutter_remaining == 0 and state.flutter_cooldown == 16,
		"water entry cancels active flutter with its cooldown"
	)
	state = actor(world)
	state.swimming = 1
	state.y = 352 * S
	tick(state, Bits.JUMP, world)
	var y: int = state.y
	check(
		state.vy == -Moves.JUMP_SPEED and state.move_water_jump == 1,
		"fresh jump at the surface starts the full jump"
	)
	tick(state, Bits.JUMP, world)
	check(
		state.vy == -Moves.JUMP_SPEED + 256 and state.y < y,
		"surface jump is not cancelled on its next held tick"
	)
	var vy: int = state.vy
	tick(state, 0, world)
	check(state.vy == vy / 4 + 256, "surface jump also respects release height")
	state = actor(world)
	state.swimming = 1
	state.y = 352 * S
	state.previous_input = Bits.JUMP
	tick(state, Bits.JUMP, world)
	check(state.move_water_jump == 0, "holding jump at a new surface does not retrigger it")
	for count in 7:
		tick(state, Bits.DOWN | Bits.RIGHT, world)
	check(
		state.move_dive == 1 and Moves.player_box(state)[3] == 14 * S,
		"moving dive changes posture when the last entry frame starts"
	)
	check(state.move_action != Moves.POUND_START, "down in water is not an air pound")
	for count in 40:
		tick(state, Bits.RIGHT, world)
	check(state.vx == 200 * 60, "swimming has its own horizontal cap")
	world = floor_world()
	world.layers.append(layer("snow64", false, false, [[4, 8]]))
	state = actor(world)
	tick(state, Bits.RIGHT, world)
	check(state.move_snow == 1 and state.vx == 192, "snow contact selects its own acceleration")
	state = actor(world)
	state.vx = 100 * 60
	tick(state, Bits.LEFT, world)
	check(
		state.vx == 100 * 60 - 1488 and state.facing == -1,
		"snow reversal faces input and uses stronger braking"
	)
	tick(state, 0, world)
	check(
		state.vx == 100 * 60 - 1488 - 1296 and state.facing == -1,
		"snow release preserves reversal facing and braking"
	)


func schema_checks() -> void:
	var state := actor(empty_world())
	for field: Array in Moves.PLAYER_FIELDS:
		state[field[0]] = 99
	state.flutter_remaining = 20
	state.flutter_cooldown = 16
	Moves.reset(state)
	for field: Array in Moves.PLAYER_FIELDS:
		check(state[field[0]] == field[1], "reset restores " + field[0])
	check(
		state.flutter_remaining == 0 and state.flutter_cooldown == 0,
		"reset also clears reused flutter timers"
	)
	check(Moves.valid_state(state), "fresh player schema is valid")
	for pair: Array in [
		["move_action", 99],
		["move_action_tick", -1],
		["move_aim_angle", 45001],
		["move_aim_dir", 0],
		["move_eggs", 7],
		["move_digest_ticks", -1],
		["move_water_transition", 10],
		["move_tongue_length", 129 * S],
		["move_dive", 2],
		["move_ammo_count", 61],
		["move_look", 0.0],
		["previous_input", 256],
		["move_emit_1_serial", 1],
		["move_emit_2_kind", 999],
		["move_emit_serial", -1],
	]:
		var invalid := state.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(not Moves.valid_state(invalid), "schema rejects invalid " + pair[0])


func pose_checks() -> void:
	var world := floor_world()
	var state := actor(world)
	tick(state, Bits.DOWN, world)
	var saved := state.duplicate(true)
	check(Pose.select(state).name == "Duck0", "view selects the crouch pose")
	check(state == saved, "pose selection is read-only")
	state.move_held_id = 42
	check(Pose.select(state).name == "Duck1", "held item selects the full-mouth pose")
	state = actor(world)
	tick(state, Bits.USE | Bits.UP, world)
	check(Pose.select(state).name == "TongueUp0", "view selects the upward action")
	state.move_action = Moves.EMIT
	state.move_ammo = Moves.SEED
	state.move_ammo_count = 3
	state.on_floor = 0
	check(
		Pose.select(state).name == "SpewSeedUpJump",
		"airborne seed emission selects its action pose"
	)


func tick(state: Dictionary, input: int, world: Dictionary) -> void:
	Sim.advance(state, input, world)
	check(Moves.valid_state(state), "step produces valid integer player state")


static func actor(world: Dictionary) -> Dictionary:
	var compiled := world.duplicate()
	compiled.erase("maps")
	world.maps = {1: compiled}
	var state := State.create(world)
	Moves.initialize(state)
	return state


static func empty_world() -> Dictionary:
	var world := {
		"identity": "synthetic".sha256_text(),
		"source": {},
		"initial_map": 1,
		"map_index": 1,
		"map_count": 1,
		"flowers_target": 0,
		"redcoins_target": 0,
		"spawn_facing": 1,
		"entities": [],
		"width": 100000 * S,
		"height": 100000 * S,
		"spawn_x": 128 * S,
		"spawn_y": 100 * S,
		"layers": [],
		"springs": [],
		"enemies": [],
		"bridges": [],
		"goals": [],
	}
	world.maps = {1: world.duplicate()}
	return world


static func floor_world() -> Dictionary:
	var world := empty_world()
	world.spawn_y = 256 * S - GAP
	var cells := []
	for column in 32:
		cells.append([column, 8])
	world.layers.append(layer("terrain", true, false, cells))
	return world


static func water_world() -> Dictionary:
	var world := empty_world()
	var cells := []
	for row in range(10, 32):
		for column in 32:
			cells.append([column, row])
	world.layers.append(layer("water", false, true, cells))
	return world


static func layer(
	name: String, solid: bool, water: bool, filled: Array, polygon := [0, 0, 1, 0, 1, 1, 0, 1]
) -> Dictionary:
	var points := World.tile_polygon(
		0, {"tile_size": [32, 32], "collision_disabled": [], "collision_polygons": {"0": polygon}}
	)
	var cells := PackedInt32Array()
	cells.resize(32 * 32)
	cells.fill(-1)
	for cell: Array in filled:
		cells[cell[1] * 32 + cell[0]] = 0
	return {
		"name": name,
		"layer": "layer1",
		"size": 32,
		"width": 32,
		"height": 32,
		"cells": cells,
		"bounds": {0: World.polygon_bounds(points)},
		"polygons": {0: points},
		"solid": solid,
		"water": water
	}


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
