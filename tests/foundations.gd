extends SceneTree
## Pure integration checks for composed state, maps, life and move dispatch.

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Maps = preload("res://src/sim/maps.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Registry = preload("res://src/sim/registry.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	map_checks()
	goal_checks()
	tongue_checks()
	respawn_checks()
	validation_checks()
	print("FOUNDATIONS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func world_for(objects: Dictionary = {}, initial_map := 1) -> Dictionary:
	var code := {
		"version": "s3.8.0",
		"name": "Rooms",
		"desc": "Synthetic integration",
		"author": 0,
		"flowers": 2,
		"redcoins": 3,
		"startpoint": {"map": initial_map, "X": 64, "Y": 100, "M": 1},
		"maps":
		{
			"map1": {"width": 4096, "height": 1024, "objects": objects},
			"map2":
			{
				"width": 2048,
				"height": 512,
				"objects":
				{"station": {"A": "o6", "X": 200, "Y": 100, "E1": 200, "E2": 100, "F": 1}}
			}
		}
	}
	var built := World.build(JSON.stringify(code), {"tilemaps": {}})
	check(built.ok, "Synthetic maps compile")
	return built.get("world", {})


func map_checks() -> void:
	var world := world_for({}, 2)
	var state := State.create(world)
	check(state.map_index == 2 and state.map_count == 2, "Creation initializes the selected map")
	check(state.flowers_target == 2 and state.redcoins_target == 3, "Creation initializes targets")
	check(state.run_spawn_map == 2 and state.life_ready == 1, "Creation initializes lifetime")
	check(
		state.entities.size() == 1 and state.entities[0].code == "o6", "Each map compiles entities"
	)
	check(state.entities[0].map_index == 2, "Entity belongs to selected map")
	var bytes := Snapshot.encode(state)
	check(not bytes.is_empty() and bytes.decode_u32(8) == 9, "Composed fields encode as v9")
	check(Maps.change(state, world, 1, 64 * S, 100 * S, Registry.spawn_map), "Map switch succeeds")
	check(state.entities.is_empty() and world.map_index == 1, "Map switch replaces entity views")
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok, "Restore syncs the saved map before matching entities")
	check(world.map_index == 2 and world.entities.size() == 1, "Restore selects matching geometry")
	if decoded.ok:
		check(Snapshot.encode(decoded.state) == bytes, "Multi-map restoration is byte exact")
	var wrong := state.duplicate(true)
	wrong.entities = [Registry.create(world.entities[0], world)]
	wrong.entities[0].map_index = 1
	Registry.attach_views(wrong)
	var invalid := Snapshot.decode(Snapshot.encode(wrong), world.identity, world)
	check(not invalid.ok and world.map_index == 2, "Rejected table does not change active geometry")


func goal_checks() -> void:
	var objects := {"goal": {"A": "o5", "X": 64, "Y": 100}}
	for index in 5:
		objects["actor%d" % index] = {
			"A": ["e1", "e2", "e3", "e5", "e20"][index], "X": 200 + index * 40, "Y": 100
		}
	objects["far"] = {"A": "e1", "X": 2000, "Y": 100}
	objects["decoration"] = {"A": "neutral_unknown", "X": 200, "Y": 100}
	var world := world_for(objects)
	var state := State.create(world)
	Sim.advance(state, 0, world)
	check(state.life_phase == Life.GOAL and not state.goal_reached, "Contact starts delayed goal")
	check(state.movement == 5, "Move finish does not replace the goal pose")
	check(state.coins == 5, "Visible active actor bodies convert once")
	for entity: Dictionary in state.entities:
		if entity.id.begins_with("actor"):
			check(entity.status == Registry.DEFEATED, "Eligible body is defeated")
		elif entity.id == "far":
			check(entity.status == Registry.WAITING, "Distant actor is not converted")
		elif entity.id == "decoration":
			check(entity.status == Registry.ACTIVE, "Inert code is not converted")
	Sim.advance(state, 0, world)
	check(state.coins == 5 and state.movement == 5, "Goal conversion is not repeated")
	check(not Snapshot.encode(state).is_empty(), "Goal sequence remains saveable")
	# An active body whose edge enters the reference area counts, not just its origin.
	var far: Array = state.entities.filter(func(item: Dictionary) -> bool: return item.id == "far")
	var actor: Dictionary = far[0]
	actor.status = Registry.ACTIVE
	actor.x = state.camera_x + 416 * S + S
	actor.y = state.camera_y
	Registry.goal_convert(state, world, Life.goal_coin)
	check(actor.status == Registry.DEFEATED and state.coins == 6, "Conversion uses body bounds")
	Registry.goal_convert(state, world, Life.goal_coin)
	check(state.coins == 6, "Defeated bodies cannot award a second coin")


func tongue_checks() -> void:
	var world := world_for()
	for facing in [-1, 1]:
		for axis in [0, 1]:
			var state := State.create(world)
			state.x = 500 * S
			state.y = 400 * S
			state.facing = facing
			state.separated = 1
			state.companion_mode = Life.BUBBLE
			state.move_action = Moves.TONGUE
			state.move_tongue_axis = axis
			state.move_tongue_phase = Moves.TONGUE_OUT
			state.move_tongue_length = 120 * S
			state.recovery_x = state.x + facing * (14 if axis else 54) * S
			state.recovery_y = state.y - (38 if axis else 0) * S
			var tip := Moves.tongue_box(state)
			var reach := Moves.tongue_reach_box(state)
			check(
				not Life.catch_companion(state, tip[0], tip[1], tip[2], tip[3]),
				"Tip misses nearby companion"
			)
			check(
				Life.catch_companion(state, reach[0], reach[1], reach[2], reach[3]),
				"Full extent catches companion"
			)
	var state := State.create(world)
	check(Moves.tongue_reach_box(state).is_empty(), "Idle tongue has no rescue extent")
	state.x = 500 * S
	state.y = 400 * S
	state.facing = 1
	state.separated = 1
	state.companion_mode = Life.BUBBLE
	state.recovery_x = 554 * S
	state.recovery_y = 400 * S
	state.move_action = Moves.TONGUE
	state.move_action_tick = 5
	state.move_tongue_phase = Moves.TONGUE_OUT
	Sim.advance(state, 0, world)
	check(state.life_phase == Life.REJOIN, "Pure step connects full tongue reach to rescue")
	check(not Snapshot.encode(state).is_empty(), "Tongue rescue remains saveable")


func respawn_checks() -> void:
	var world := world_for()
	var state := State.create(world)
	state.move_eggs = 4
	state.move_action = Moves.TONGUE
	state.move_tongue_phase = Moves.TONGUE_OUT
	state.swimming = 1
	state.water_phase = 12
	state.jump_buffer = 6
	Life.kill(state, Life.QUICK, true)
	state.life_phase = Life.RESPAWN
	Sim.advance(state, 255, world)
	check(state.life_phase == Life.FADE_IN, "Pure step runs the respawn callback")
	check(
		state.move_eggs == 0 and state.move_action == Moves.NORMAL,
		"Respawn resets move-owned fields"
	)
	check(
		state.move_tongue_phase == Moves.TONGUE_NONE and state.jump_buffer == 0,
		"Respawn clears action residue"
	)
	check(state.swimming == 0 and state.water_phase == 0, "Respawn clears base water state")
	check(not Snapshot.encode(state).is_empty(), "Respawn remains saveable")


func validation_checks() -> void:
	var world := world_for()
	var state := State.create(world)
	state.previous_input = 255
	state.pressed_input = 255
	state.jump_buffer = 6
	state.flutter_remaining = 72
	state.hurt_deceleration = 128
	check(not Snapshot.encode(state).is_empty(), "Widened base fields are accepted")
	for example: Array in [
		["previous_input", 256],
		["pressed_input", 256],
		["jump_buffer", 7],
		["flutter_remaining", 73],
		["flutter_cooldown", 18],
		["water_phase", 60],
		["swimming", 2]
	]:
		var invalid := state.duplicate(true)
		invalid[example[0]] = example[1]
		check(not Snapshot.valid_state(invalid), "Invalid base field is rejected: " + example[0])
	for example: Array in [["move_eggs", 7], ["health", 31], ["map_index", 3]]:
		var invalid := state.duplicate(true)
		invalid[example[0]] = example[1]
		check(not Snapshot.valid_state(invalid), "Owner hook rejects: " + example[0])


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
