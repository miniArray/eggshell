extends SceneTree
## Pure enemy checks use invented placements, geometry and input states only.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Moves = preload("res://src/sim/moves.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Collision = preload("res://src/sim/collision.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Hits = preload("res://src/sim/hits.gd")
const Life = preload("res://src/sim/life.gd")
const S := preload("res://src/sim/units.gd").SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	registration_checks()
	runtime_option_checks()
	movement_checks()
	liquid_checks()
	dry_fish_checks()
	lava_checks()
	contact_checks()
	capture_teardown_checks()
	flat_support_pound_check()
	food_checks()
	upward_spit_checks()
	egg_checks()
	goal_checks()
	replay_checks()
	if State.level_fields().any(func(pair: Array) -> bool: return pair[0] == "dynamic_serial"):
		runtime_checks()
	else:
		print("S6_ENEMIES_RUNTIME_BLOCKED: runtime registry integration is not present")
	print("S6_ENEMIES_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _world_for(objects: Dictionary, floor: bool = true) -> Dictionary:
	var world := {
		"identity": "invented enemy checks".sha256_text(),
		"spawn_x": 64 * S,
		"spawn_y": 160 * S,
		"spawn_facing": 1,
		"map_index": 1,
		"initial_map": 1,
		"map_count": 1,
		"flowers_target": 0,
		"redcoins_target": 0,
		"width": 4096 * S,
		"height": 1024 * S,
		"layers": []
	}
	var records := objects.duplicate(true)
	if floor:
		records["floor"] = {"A": "p1", "X": 0, "Y": 176, "E1": 4096}
	var result := Registry.compile_map(records, world)
	_check(result.ok, "Synthetic enemy source compiles")
	world.maps = {1: world.duplicate()}
	return world


func _fixture(code: String, options: Dictionary = {}, floor: bool = true) -> Dictionary:
	var source := {"A": code, "X": 128, "Y": 136 if code == "e28" else 144}
	source.merge(options, true)
	var world := _world_for({"unit": source}, floor)
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	entity.status = 1
	Collision.begin_step(state, world, Registry)
	return {"world": world, "state": state, "entity": entity, "type": Registry.lookup(code)}


func registration_checks() -> void:
	for code: String in ["e4", "e6", "e8", "e11", "e21", "e28", "e31", "e41"]:
		_check(Registry.implemented(code), "Enemy code is registered: " + code)
		var unit := _fixture(code)
		_check(Registry.valid(unit.entity), code + " starts with valid declared integer state")
		_check(unit.state.enemies.size() == 1, code + " joins the enemy read view")
	for code: String in ["e1", "e2", "e6", "e8", "e11", "e21"]:
		var maximum := 4 if code in ["e1", "e2", "e6", "e8"] else 3
		for variant: int in range(maximum + 1):
			var unit := _fixture(code, {"F": variant, "M": 2})
			_check(
				unit.entity.variant == variant and unit.entity.mirror == 2,
				code + " saves its placement options"
			)
		var invalid := {}
		var result := Registry.compile_map(
			{"invalid": {"A": code, "X": 0, "Y": 0, "F": maximum + 1}}, invalid
		)
		_check(
			result.ok and invalid.entities[0].code == "?" + code and invalid.enemies.is_empty(),
			code + " degrades an unbuilt variant to a placeholder outside the enemy view"
		)
		result = Registry.compile_map({"invalid": {"A": code, "X": 0, "Y": 0, "M": "1"}}, invalid)
		_check(not result.ok, code + " rejects a nonnumeric mirror")
	var unit := _fixture("e1", {"E1": "Static", "F": 4})
	_check(unit.entity.variant == 4, "An unused legacy field does not change the walker")


func runtime_option_checks() -> void:
	var type: Script = Registry.lookup("e4")
	var source := {"code": "e4", "source_index": -1, "x": 0, "y": 0, "properties": {"vx": "fast"}}
	_check(not type.prepare(source, {}).ok, "Runtime enemy vectors reject noninteger input")
	source.properties = {"facing": 0}
	_check(not type.prepare(source, {}).ok, "Runtime enemy direction rejects zero")
	source.properties = {"F": 0, "M": 1, "facing": -1, "vx": 120 * 60, "vy": -256 * 60}
	_check(type.prepare(source, {}).ok, "Runtime options share the editor prepare path")
	var values: Dictionary = type.create(source, {})
	_check(
		values.vx == 120 * 60 and values.facing == -1 and values.spawn_mode == 0,
		"Runtime creation saves validated vectors and facing"
	)
	var unit := _fixture("e4", {"vx": 999, "facing": 0})
	_check(
		unit.entity.vx == 0 and unit.entity.facing == -1,
		"Placed actors do not consume private runtime-only fields"
	)


func movement_checks() -> void:
	for code: String in ["e4", "e6", "e8", "e31"]:
		var unit := _fixture(code, {"M": 1})
		if code == "e31":
			unit.entity.queued = 0
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(unit.entity.vx == 48 * 60, code + " walks at its declared speed")
		_check(unit.entity.x > 128 * S, code + " advances through real collision")
	for code: String in ["e6", "e8"]:
		var unit := _fixture(code, {"F": 1})
		for tick: int in 18:
			unit.type.step(unit.entity, unit.state, unit.world)
		_check(unit.entity.vy < 0, code + " winged hopping leaves the floor")
		unit = _fixture(code, {"F": 2}, false)
		unit.type.step(unit.entity, unit.state, unit.world)
		if code == "e6":
			_check(
				unit.entity.vx == -144 * 60 and unit.entity.vy == 0,
				"First winged colour has horizontal flight"
			)
		else:
			_check(
				unit.entity.vx == 0 and unit.entity.vy == -112 * 60,
				"Second winged colour has vertical flight"
			)
		unit = _fixture(code, {"F": 3})
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(unit.entity.vx == 0, code + " empty shell stays stopped")
		unit = _fixture(code, {"F": 4})
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(unit.entity.vx == -432 * 60, code + " fourth variant begins spinning")
	for variant: int in 4:
		var unit := _fixture("e11", {"F": variant})
		for tick: int in 7:
			unit.type.step(unit.entity, unit.state, unit.world)
		_check(
			(unit.entity.vy < 0) == (variant % 2 == 1), "Armor variants select walking or jumping"
		)
	var unit := _fixture("e28")
	unit.state.x = -400 * S
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(
		unit.entity.mode == 0 and unit.entity.y == 136 * S,
		"Overhead actor waits outside its trigger range"
	)
	unit.state.x = unit.entity.x
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(
		unit.entity.mode == 2 and unit.entity.landed == 1,
		"Overhead actor drops and records its first landing"
	)
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(absi(unit.entity.vx) == 320 * 60, "Landed overhead actor rolls at its declared speed")
	unit = _fixture("e28")
	_water(unit.world)
	unit.world.layers[0].water = false
	unit.world.layers[0].solid = true
	unit.world.layers[0].cells.fill(-1)
	unit.world.layers[0].cells[8 * 128 + 5] = 0
	unit.entity.mode = 2
	unit.entity.landed = 1
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(unit.entity.status == 2, "Roller's 29 pixel wall probe despawns before body overlap")
	fish_checks()


func _water(world: Dictionary) -> void:
	var cells := PackedInt32Array()
	cells.resize(128 * 64)
	cells.fill(-1)
	for row: int in range(9, 64):
		for column: int in 128:
			cells[row * 128 + column] = 0
	world.layers = [
		{
			"name": "unit_water",
			"layer": "layer1",
			"size": 16,
			"width": 128,
			"height": 64,
			"cells": cells,
			"bounds": {0: [0, 0, 16 * S, 16 * S]},
			"polygons": {0: PackedInt64Array([0, 0, 16 * S, 0, 16 * S, 16 * S, 0, 16 * S])},
			"solid": false,
			"water": true
		}
	]


func fish_checks() -> void:
	for variant: int in 4:
		var unit := _fixture("e21", {"F": variant, "X": 600, "Y": 152}, false)
		_water(unit.world)
		unit.state.x = 300 * S
		unit.state.camera_x = unit.entity.x
		var jumped := false
		for tick: int in 500:
			unit.type.step(unit.entity, unit.state, unit.world)
			jumped = jumped or unit.entity.mode in [2, 3, 4]
		_check(jumped == (variant != 0), "Fish variant selects patrol or a jump cycle")
		_check(Registry.valid(unit.entity), "Fish variant retains a valid saved state")
		if variant == 3:
			_check(
				unit.entity.hidden == 1 and unit.entity.fish_jumps == 0,
				"Chained fish hides after its third completed arc"
			)


func lava_checks() -> void:
	for code: String in ["e1", "e4", "e6", "e11", "e28", "e31", "e41"]:
		var unit := _fixture(code, {"Y": 220}, false)
		_water(unit.world)
		unit.world.layers[0].name = "lava"
		if code == "e28":
			unit.state.y = 300 * S
		if code == "e1":
			unit.type.start_roll(unit.entity, 1, 0, false)
		elif code == "e4":
			unit.entity.spat = 1
			unit.entity.spit_speed = 256 * 60
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(unit.entity.status == 3, code + " lava removes normal or destructive actors")


func dry_fish_checks() -> void:
	var directions := {}
	for seed_value: int in [1, 2, 3, 4, 5, 6]:
		var unit := _fixture("e21")
		unit.state.rng = seed_value
		for tick: int in 12:
			unit.type.step(unit.entity, unit.state, unit.world)
			if unit.entity.fish_dry:
				directions[unit.entity.facing] = true
				_check(
					unit.entity.vy in [-256 * 60, -384 * 60],
					"Dry fish chooses one of its two source jump impulses"
				)
				break
	_check(directions.size() == 2, "Dry fish RNG can select either facing")


func liquid_checks() -> void:
	var unit := _fixture("e4", {"Y": 220}, false)
	_water(unit.world)
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(
		unit.entity.vx == -24 * 60 and unit.entity.vy == 512,
		"Liquid halves fixed walking speed and quarters gravity"
	)
	unit = _fixture("e6", {"F": 1, "Y": 220}, false)
	_water(unit.world)
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(
		unit.entity.vx == -16 * 60 and unit.entity.vy == 128,
		"Winged shell combines its liquid speed and gravity rules"
	)


func contact_checks() -> void:
	for code: String in ["e4", "e6", "e8", "e11", "e21", "e28", "e31", "e41"]:
		var unit := _fixture(code)
		unit.state.x = unit.entity.x + 10 * S
		unit.state.y = unit.entity.y + 16 * S
		unit.type.contact(unit.entity, unit.state, unit.world, 0)
		_check(
			unit.state.hits == 1 and unit.state.deaths == 0 and unit.state.separated == 1,
			code + " contact uses the life damage path"
		)
	var unit := _fixture("e4")
	unit.state.x = unit.entity.x
	unit.state.y = unit.entity.y - 8 * S
	unit.type.contact(unit.entity, unit.state, unit.world, 0)
	_check(
		unit.entity.status == 1 and unit.entity.mode == 4 and unit.state.vy < 0,
		"Stomp flattens rather than defeats the small walker"
	)
	_check(
		not unit.type.solid_box(unit.entity).is_empty(), "Flattened walker exposes top-only support"
	)
	unit.entity.contact = 0
	unit.state.y = unit.entity.y + 4 * S
	unit.state.move_action = Moves.POUND_FALL
	unit.type.contact(unit.entity, unit.state, unit.world, 0)
	_check(unit.entity.status == 3, "Pound defeats the flattened walker")
	for code: String in ["e11", "e28", "e31", "e21"]:
		unit = _fixture(code)
		unit.state.x = unit.entity.x
		unit.state.y = unit.entity.y - 12 * S
		unit.state.move_action = Moves.POUND_FALL
		unit.type.contact(unit.entity, unit.state, unit.world, 0)
		if code == "e11":
			_check(
				unit.entity.status == 1 and unit.state.hits == 1,
				"Armor resists a pound and hurts the player"
			)
		elif code == "e28":
			_check(
				(
					unit.entity.status == 1
					and unit.state.vy < 0
					and unit.state.move_action == Moves.NORMAL
				),
				"Overhead actor bounces and cancels a pound"
			)
		else:
			_check(unit.entity.status == 3, code + " is defeated by a pound")


func flat_support_pound_check() -> void:
	var unit := _fixture("e4")
	unit.entity.mode = 5
	unit.state.x = unit.entity.x
	unit.state.y = unit.entity.y + 2 * S - S / 16
	unit.state.on_floor = 1
	Sim.advance(unit.state, 0, unit.world)
	_check(
		unit.state.x == unit.entity.x and unit.state.x < 128 * S,
		"Real collision carries a rider on the moving flattened walker"
	)
	unit = _fixture("e4")
	unit.entity.mode = 5
	unit.state.x = unit.entity.x
	unit.state.y = unit.entity.y - 40 * S
	unit.state.move_action = Moves.POUND_FALL
	unit.state.vy = 1408 * 60
	for tick: int in 3:
		Sim.advance(unit.state, InputBits.DOWN, unit.world)
	_check(
		unit.entity.status == 3 and unit.state.deaths == 0,
		"Real pound collision calls the flattened support's bump hook"
	)


func capture_teardown_checks() -> void:
	var unit := _fixture("e5")
	unit.entity.mode = 4
	unit.entity.timer = 210
	unit.entity.head_size = 15
	unit.entity.pin_size = 15
	unit.entity.head_dx = S
	unit.state.captured_by = unit.entity.family_index + 1
	unit.type.hit(unit.entity, unit.state, unit.world, Hits.CLEAR, unit.state.x)
	_check(
		unit.entity.status == 3 and unit.state.captured_by == 0 and unit.state.separated == 1,
		"Destroying a captor releases player and companion before removal"
	)


func _catch_food(unit: Dictionary) -> void:
	unit.state.move_action = Moves.TONGUE
	unit.state.move_tongue_phase = Moves.TONGUE_OUT
	_check(
		unit.type.tongue(unit.entity, unit.state, unit.world) == 1, "Tongue catches an edible enemy"
	)
	_check(
		unit.entity.held == 1 and unit.state.move_held_id == unit.entity.token,
		"Held identity is the saved stable token"
	)


func food_checks() -> void:
	for code: String in ["e1", "e2", "e4", "e31"]:
		var unit := _fixture(code, {"F": 4} if code in ["e1", "e2"] else {})
		_catch_food(unit)
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(
			unit.entity.x == unit.state.x + 24 * S, "Held enemy pins to the mouth and does not move"
		)
		unit.state.move_action_tick = 11
		Moves.advance(unit.state, 0, unit.world, 0, 0)
		Moves.advance(unit.state, InputBits.DOWN, unit.world, InputBits.DOWN, 0)
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(
			unit.entity.status == 3 and unit.entity.held == 0,
			"Actual lay request consumes its held enemy once"
		)
		for tick: int in 18:
			Moves.advance(unit.state, 0, unit.world, 0, 0)
		_check(unit.state.move_eggs == 1, "Digestible enemy supplies one stored egg through Moves")
		unit = _fixture(code)
		_catch_food(unit)
		unit.state.move_action_tick = 11
		Moves.advance(unit.state, 0, unit.world, 0, 0)
		Moves.advance(unit.state, InputBits.USE, unit.world, InputBits.USE, 0)
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(
			unit.entity.held == 0 and (unit.entity.spat == 1 or unit.entity.get("roll", 0) == 1),
			"Actual spit request releases the same saved enemy"
		)
		_check(
			unit.entity.request_cursor == unit.state.move_emit_serial,
			"Enemy saves its request cursor"
		)
	for code: String in ["e6", "e8"]:
		var unit := _fixture(code, {"F": 3})
		_catch_food(unit)
		_check(unit.state.move_digest == 0, "An empty shell is held but not digestible")
	var unit := _fixture("e21")
	_catch_food(unit)
	_check(unit.state.move_instant == 1, "Fish uses the instant swallow contract")
	unit.state.move_action_tick = 11
	Moves.advance(unit.state, 0, unit.world, 0, 0)
	unit.type.step(unit.entity, unit.state, unit.world)
	_check(
		unit.entity.status == 3 and unit.state.move_held_id == 0,
		"Instant swallow consumes fish through its emitted request"
	)
	unit = _fixture("e11")
	_check(
		unit.type.tongue(unit.entity, unit.state, unit.world) == 2 and unit.entity.vx == 128 * 60,
		"Tongue blocks on armor and pushes it"
	)


func upward_spit_checks() -> void:
	for code: String in ["e1", "e2", "e4", "e6", "e8", "e31"]:
		var unit := _fixture(code)
		_catch_food(unit)
		unit.state.move_action_tick = 11
		Moves.advance(unit.state, 0, unit.world, 0, 0)
		Moves.advance(
			unit.state, InputBits.UP | InputBits.USE, unit.world, InputBits.USE | InputBits.UP, 0
		)
		var request := Moves.spawn_request(unit.state)
		_check(
			request.vx == 0 and request.vy == -768 * 60,
			"Upward spit emits a vertical authoritative vector"
		)
		unit.type.step(unit.entity, unit.state, unit.world)
		_check(
			unit.entity.held == 0 and unit.entity.vx == 0,
			code + " applies an upward spit without horizontal drift"
		)
		if code in ["e1", "e2"]:
			_check(unit.entity.roll_up == 1, "Upward spit selects the timed rolling branch")
		if code in ["e6", "e8"]:
			_check(unit.entity.inside == 1, "Spitting a shell does not erase its resident body")


func _egg_payload(unit: Dictionary) -> Dictionary:
	return {
		"code": "egg",
		"token": 900001,
		"x": unit.entity.x - 8 * S,
		"y": unit.entity.y,
		"vx": 256 * 60,
		"vy": 0,
		"fall_on_terrain": 0
	}


func egg_checks() -> void:
	for code: String in ["e4", "e31"]:
		var unit := _fixture(code)
		var egg := _egg_payload(unit)
		_check(
			unit.type.projectile_contact(unit.entity, egg, unit.state, unit.world) == 3,
			code + " lets the striking egg continue"
		)
		_check(
			unit.entity.status == 3 and egg.fall_on_terrain == 1,
			code + " sets the next-terrain falling flag"
		)
	for code: String in ["e1", "e2"]:
		var unit := _fixture(code)
		_check(
			(
				(
					unit.type.projectile_contact(
						unit.entity, _egg_payload(unit), unit.state, unit.world
					)
					== 1
				)
				and unit.entity.roll == 1
			),
			"Egg rolls an existing walker and is consumed"
		)
		_check(
			absi(unit.entity.vx) == 432 * 60 and unit.entity.ground_form == 1,
			"Rolled flyer loses its winged movement"
		)
	var unit := _fixture("e11")
	_check(
		unit.type.projectile_contact(unit.entity, _egg_payload(unit), unit.state, unit.world) == 1,
		"Armor consumes a striking egg"
	)
	_check(
		unit.entity.mode == 4 and unit.entity.vx == 256 * 60 and unit.entity.vy == -384 * 60,
		"Egg starts armor's rolling reaction"
	)
	for tick: int in 90:
		unit.type.step(unit.entity, unit.state, unit.world)
	_check(unit.entity.mode == 5, "Armor rolls for ninety ticks, then recovers")
	unit = _fixture("e28")
	unit.state.x = -400 * S
	_check(
		unit.type.projectile_contact(unit.entity, _egg_payload(unit), unit.state, unit.world) == 1,
		"Hanging actor consumes an egg"
	)
	_check(
		unit.entity.mode == 1 and unit.entity.timer == 81,
		"Egg starts the overhead actor's laugh cycle"
	)
	for tick: int in 81:
		unit.type.step(unit.entity, unit.state, unit.world)
	_check(unit.entity.mode == 2, "Laugh completes before the actor drops")
	_check(
		unit.type.projectile_contact(unit.entity, _egg_payload(unit), unit.state, unit.world) == 0,
		"Rolling overhead actor ignores an egg without fallback"
	)
	unit = _fixture("e41")
	for remaining: int in [2, 1, 0]:
		unit.type.hit(unit.entity, unit.state, unit.world, Hits.EGG, unit.entity.x - S)
		_check(unit.entity.hp == remaining, "Stem records each of its three hits")
	_check(unit.entity.mode == 5, "Final stem hit starts its saved defeat sequence")
	for tick: int in 105:
		unit.type.step(unit.entity, unit.state, unit.world)
	_check(unit.entity.status == 3, "Stem finishes its defeat sequence")
	unit = _fixture("e41")
	var head: Array = unit.type.head_box(unit.entity)
	var center := [(head[0] + head[2]) / 2, (head[1] + head[3]) / 2]
	_check(
		Body.polygon_overlap(
			unit.type.head_hull(unit.entity),
			[center[0] - S, center[1] - S, center[0] + S, center[1] + S]
		),
		"Rotated head hull contains its center"
	)
	_check(
		not Body.polygon_overlap(
			unit.type.head_hull(unit.entity),
			[head[2] + S, head[3] + S, head[2] + 2 * S, head[3] + 2 * S]
		),
		"Rotated head hull rejects a separate box"
	)


func goal_checks() -> void:
	for code: String in ["e4", "e6", "e8", "e11", "e21", "e28", "e31", "e41"]:
		var unit := _fixture(code)
		Registry.goal_convert(
			unit.state, unit.world, func(state: Dictionary) -> void: state.coins += 1
		)
		_check(
			unit.state.coins == 1 and unit.entity.status == 3, code + " converts to one goal coin"
		)
	var unit := _fixture("e21")
	unit.entity.hidden = 1
	Registry.goal_convert(unit.state, unit.world, func(state: Dictionary) -> void: state.coins += 1)
	_check(unit.state.coins == 0, "Hidden fish does not make a goal coin")
	unit = _fixture("e4")
	unit.entity.held = 1
	Registry.goal_convert(unit.state, unit.world, func(state: Dictionary) -> void: state.coins += 1)
	_check(unit.state.coins == 0, "Held enemy does not make a goal coin")


func replay_checks() -> void:
	for code: String in ["e4", "e6", "e8", "e11", "e21", "e28", "e31", "e41"]:
		var unit := _fixture(code)
		for tick: int in 20:
			Sim.advance(unit.state, 0, unit.world)
		_check(Snapshot.valid_state(unit.state), code + " is valid after real simulation steps")
		var decoded := Snapshot.decode(Snapshot.encode(unit.state), unit.world.identity)
		_check(
			decoded.ok and Snapshot.encode(decoded.state) == Snapshot.encode(unit.state),
			code + " snapshot round trip"
		)
		if not decoded.ok:
			continue
		for tick: int in 80:
			Sim.advance(unit.state, 0, unit.world)
			Sim.advance(decoded.state, 0, unit.world)
		_check(
			Snapshot.encode(unit.state) == Snapshot.encode(decoded.state),
			code + " future matches after restore"
		)


func runtime_checks() -> void:
	var food := _fixture("e4")
	Sim.advance(food.state, InputBits.USE, food.world)
	for tick: int in 12:
		Sim.advance(food.state, 0, food.world)
	_check(
		food.entity.held == 1 and food.state.move_held_id == food.entity.token,
		"Real tongue dispatch catches and keeps its enemy active"
	)
	Sim.advance(food.state, InputBits.DOWN, food.world)
	Sim.advance(food.state, 0, food.world)
	_check(
		food.entity.status == 3 and food.state.move_held_id == 0,
		"Registry steps held enemies to consume real lay requests"
	)
	var trap := _fixture("e28")
	trap.state.x = -400 * S
	var weapon: Dictionary = Registry.spawn_dynamic(
		trap.state, trap.world, "e6", trap.entity.x, trap.entity.y, {"F": 4}
	)
	_check(not weapon.is_empty(), "Persistent weapon uses real dynamic creation")
	if not weapon.is_empty():
		_check(
			trap.type.projectile_contact(trap.entity, weapon, trap.state, trap.world) == 3,
			"Persistent weapon starts an entry reaction"
		)
		trap.entity.timer = 70
		_check(
			(
				trap.type.projectile_contact(trap.entity, weapon, trap.state, trap.world) == 0
				and trap.entity.timer == 70
			),
			"Ongoing contact does not restart the reaction"
		)
		var memory: Array = trap.state.entities.filter(
			func(entity: Dictionary) -> bool: return entity.code == "enemy_overlap"
		)
		_check(memory.size() == 1, "One saved contact record owns entry memory")
		var restored := Snapshot.decode(Snapshot.encode(trap.state), trap.world.identity)
		_check(restored.ok, "Persistent contact memory round trips")
	var unit := _fixture("e31")
	for tick: int in 53:
		Sim.advance(unit.state, 0, unit.world)
	var pellets: Array = unit.state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "enemy_pellet"
	)
	_check(
		pellets.size() == 1 and pellets[0].source_index == -1,
		"Shooter appends a real saved dynamic projectile"
	)
	unit = _fixture("e6")
	unit.state.x = unit.entity.x - S
	unit.state.y = unit.entity.y - 12 * S
	unit.type.contact(unit.entity, unit.state, unit.world, 0)
	var runners: Array = unit.state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "enemy_runner"
	)
	_check(runners.size() == 1, "Stomp releases a real dynamic runner")
	if runners.is_empty():
		return
	_check(
		(
			unit.entity.runner_token == runners[0].token
			and runners[0].origin_shell == unit.entity.token
		),
		"Runner and shell save stable mutual tokens"
	)
	_check(unit.entity.can_despawn == 0, "Runner keeps its shell loaded")
	var registry: Script = Registry
	var spike: Dictionary = registry.spawn_dynamic(
		unit.state, unit.world, "enemy_spike", 700 * S, 100 * S, {"vx": 384 * 60, "vy": -768 * 60}
	)
	_check(
		not spike.is_empty() and spike.vx == 384 * 60 and spike.vy == -768 * 60,
		"Ballistic projectile saves its initial vectors"
	)
	var decoded := Snapshot.decode(Snapshot.encode(unit.state), unit.world.identity)
	_check(decoded.ok, "Dynamic enemy state round trips through the real codec")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)


## Entities run one world tick at level start, as in the original. These unit checks
## start from the placement, so the table is spawned again after the level start.
func _placed_state(world: Dictionary) -> Dictionary:
	var state := State.create(world)
	Registry.spawn_map(state, world)
	return state
