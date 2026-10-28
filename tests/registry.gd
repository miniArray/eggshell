extends SceneTree
## Fast pure-state checks on invented placements. No scenes, assets or recordings.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const World = preload("res://src/sim/world.gd")
const Sim = preload("res://src/sim/step.gd")
const Units = preload("res://src/sim/units.gd")
const S := Units.SCALE
const FIXTURE_OPTIONS := {
	"e9": {"M": 2},
	"enemy_overlap": {"a": 1, "b": 2},
	"o12": {"F": 1},
	"o17": {"E1": "o7"},
	"o23": {"E2": "0"},
	"o29": {"F": 2},
	"o8": {"E1": "1", "E2": "5"},
	"p2": {"E1": "160"},
	# slice 8: objects B
	"o30": {"F": 1},
	"p6": {"E1": "96", "E2": "32"},
	"p9": {"E1": "96"},
	"p11": {"E1": "96", "E2": "1"},
	"p12": {"E1": "96"},
	"o21": {"E1": "0", "E2": "128", "E3": "1.5", "F": 5, "R": 90},
	"e23": {"M": 1},
	"e24": {"M": 2},
	"e33": {"R": 270, "M": 1},
	"o33": {"E1": "255", "E2": "0", "E3": "0", "E4": "1"},
	"o34": {"E1": "255", "E2": "0", "E3": "0", "E4": "1", "F": 1},
}
var checks := 0
var failures := 0


func _initialize() -> void:
	registry_checks()
	schema_checks()
	placement_checks()
	checkpoint_flag_checks()
	checkpoint_type_checks()
	snapshot_checks()
	lifecycle_checks()
	contact_checks()
	step_check()
	print("REGISTRY_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func world_for(objects: Dictionary = {}) -> Dictionary:
	var has_maps := State.level_fields().any(
		func(pair: Array) -> bool: return pair[0] == "map_index"
	)
	var world := {
		"identity": "synthetic entity world".sha256_text(),
		"spawn_x": 64 * S,
		"spawn_y": 100 * S,
		"spawn_facing": 1,
		"map_index": 1 if has_maps else 0,
		"initial_map": 1,
		"map_count": 1,
		"flowers_target": 0,
		"redcoins_target": 0,
		"width": 4096 * S,
		"height": 1024 * S,
		"layers": []
	}
	var result := World.setup_objects({"objects": objects}, world)
	check(result.ok, "Synthetic placements compile")
	world.maps = {1: world.duplicate()}
	return world


func mixed_world() -> Dictionary:
	return world_for(
		{
			"unknown":
			{
				"A": "neutral_unknown",
				"X": 12,
				"Y": 20,
				"E1": "text",
				"E2": [1, 2],
				"E3": {"option": true},
				"E4": null,
				"F": 11,
				"M": 2,
				"R": 90,
				"future": "kept"
			},
			"pad": {"A": "o11", "X": 200, "Y": 84, "F": 3},
			"actor": {"A": "e1", "X": 100, "Y": 100},
			"bridge": {"A": "p1", "X": 300, "Y": 100, "E1": "64"},
			"goal": {"A": "o5", "X": 400, "Y": 100}
		}
	)


func registry_checks() -> void:
	for code: String in ["o5", "o6", "o11", "p1", "e1", "e2", "e3", "e5", "e20"]:
		check(Registry.implemented(code), "Baseline code stays registered: " + code)
	var registered := {}
	for code: String in Registry.codes():
		check(not registered.has(code), "Object codes are unique: " + code)
		registered[code] = true
	for code: String in Registry.codes():
		var type: Script = Registry.lookup(code)
		check(code in type.CODES, "Lookup selects declaring module " + code)
		check(
			type.has_method("create") and type.has_method("step") and type.has_method("valid"),
			"Type contract " + code
		)
		var names := []
		for pair: Array in Registry.fields(code):
			check(
				(
					pair.size() == 2
					and pair[0] is String
					and pair[1] is int
					and not names.has(pair[0])
				),
				"Ordered unique int64 entity field"
			)
			names.append(pair[0])
	check(not Registry.implemented("neutral_unknown"), "Unknown code stays unsupported")
	check(Registry.lookup("neutral_unknown") == Registry.Inert, "Unknown type is inert")


func schema_checks() -> void:
	var fields := State.compose([[["one", 0], ["two", 2]], [["one", 7], ["three", 3]]])
	check(fields == [["one", 7], ["two", 2], ["three", 3]], "Schema extension is stable and unique")
	var names := []
	for pair: Array in State.fields():
		check(pair[1] is int and not names.has(pair[0]), "Scalar schema contains each int64 once")
		names.append(pair[0])
	for key: String in [
		"hurt",
		"invulnerable",
		"health",
		"health_wait",
		"separated",
		"recovery_x",
		"recovery_y",
		"recovery_delay",
		"hits",
		"hurt_deceleration"
	]:
		check(
			not State.BASE_PLAYER_FIELDS.any(func(pair: Array) -> bool: return pair[0] == key),
			"Lifetime owner keeps " + key
		)
	var state := State.create(world_for())
	check(
		state.health == 10 and state.rng == 1 and state.facing == 1,
		"Composed defaults initialize state"
	)
	check(
		Snapshot.count_offset() == Snapshot.HEADER + State.fields().size() * 8,
		"Layout follows composed schema"
	)
	var mirrored := world_for()
	mirrored.spawn_facing = -1
	check(State.create(mirrored).facing == -1, "Compiled spawn facing initializes player")


func placement_checks() -> void:
	var world := mixed_world()
	var state := State.create(world)
	check(state.entities.size() == 5, "Every placement becomes an entity")
	check(
		state.entities[0].id == "unknown" and state.entities[0].source_index == 0,
		"String placement id and ordered source slot are separate"
	)
	check(
		(
			state.entities.map(func(entity: Dictionary) -> String: return entity.code)
			== ["neutral_unknown", "o11", "e1", "p1", "o5"]
		),
		"Placement order is stable"
	)
	check(
		world.entities[0].properties.E2 == [1, 2] and world.entities[0].properties.future == "kept",
		"Unknown property shapes retained"
	)
	check(
		(
			state.entities[1].y == 100 * S
			and state.entities[1].large == 1
			and state.entities[1].single_use == 1
		),
		"Pad placement and variant retained"
	)
	check(
		world.bridges[0].left == 268 * S and world.bridges[0].top == 84 * S,
		"Bridge geometry retained"
	)
	state.enemies[0].timer = 23
	check(state.entities[2].timer == 23, "Compatibility views share entity dictionaries")
	state.health = 7
	state.deaths = 3
	Registry.spawn_map(state, world)
	check(
		state.entities[2].timer == 0 and state.health == 7 and state.deaths == 3,
		"Map reset recreates entities without clearing counters"
	)
	var before: Dictionary = state.entities[0].duplicate(true)
	Registry.advance(state, world, 0)
	check(state.entities[0] == before, "Unknown entity stays inert")


func checkpoint_flag_checks() -> void:
	var world := mixed_world()
	var state := State.create(world)
	state.entities[0].collected = 1
	state.entities[0].checkpoint_collected = 0
	state.entities[2].collected = 0
	state.entities[2].checkpoint_collected = 1
	var result := World.setup_objects(
		{
			"objects":
			{
				"actor": {"A": "e1", "X": 100, "Y": 100},
				"unknown": {"A": "neutral_unknown", "X": 12, "Y": 20}
			}
		},
		world
	)
	check(result.ok, "Reordered stable placements compile")
	world.erase("maps")
	world.maps = {1: world.duplicate()}
	Registry.spawn_map(state, world, true)
	check(
		state.entities[0].id == "actor" and state.entities[0].source_index == 0,
		"Respawn lookup follows stable id, not former array slot"
	)
	check(
		state.entities[0].collected == 1 and state.entities[0].checkpoint_collected == 1,
		"Checkpoint collection survives same-map respawn"
	)
	check(
		state.entities[1].collected == 0 and state.entities[1].checkpoint_collected == 0,
		"Later collection rolls back to checkpoint"
	)
	var decoded := Snapshot.decode(Snapshot.encode(state), world.identity, world)
	check(
		decoded.ok and decoded.state.entities[0].checkpoint_collected == 1,
		"Collection flags survive snapshot"
	)
	Registry.spawn_map(state, world)
	for entity: Dictionary in state.entities:
		check(
			entity.collected == 0 and entity.checkpoint_collected == 0,
			"Default map reset clears both flags"
		)


func checkpoint_type_checks() -> void:
	var world := world_for({"station": {"A": "o6", "X": 10, "Y": 20, "E1": "-12.5", "E2": 128}})
	var state := State.create(world)
	check(
		state.entities[0].respawn_x == -45_000 and state.entities[0].respawn_y == 128 * S,
		"Checkpoint parses string and numeric target positions"
	)
	check(Registry.lookup("o6") == Registry.Checkpoint, "Checkpoint uses lifetime hook module")
	check(state.entities[0].health_bonus == 10, "Ordinary checkpoint defaults to ten")
	var refill := world_for({"refill": {"A": "o6", "X": 10, "Y": 20, "E1": "0", "E2": "0", "F": 1}})
	check(
		State.create(refill).entities[0].health_bonus == 30, "Full-refill variant supplies thirty"
	)
	var other := world_for({"other": {"A": "o6", "X": 10, "Y": 20, "E1": "0", "E2": "0", "F": 7}})
	check(
		State.create(other).entities[0].health_bonus == 10,
		"Other variants do not invent more meanings"
	)
	for code: String in ["e1", "o11"]:
		var oversized := World.setup_objects(
			{"objects": {"large": {"A": code, "X": 0, "Y": 0, "F": 1e100}}}, {}
		)
		check(not oversized.ok, "Oversized variant rejected before integer conversion")
	for option: Variant in ["not a number", INF, true, [], null]:
		var invalid := World.setup_objects(
			{"objects": {"bridge": {"A": "p1", "X": 0, "Y": 0, "E1": option}}}, {}
		)
		check(not invalid.ok, "Malformed bridge option rejected explicitly")


func snapshot_checks() -> void:
	var world := mixed_world()
	var state := State.create(world)
	state.frame = 123
	state.entities[0].x = -9223372036854775807
	state.entities[2].status = 1
	state.entities[2].timer = 37
	state.entities[1].squash = 7
	var bytes := Snapshot.encode(state)
	check(not bytes.is_empty() and bytes.decode_u32(8) == 6, "Version six bytes encoded")
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok, "Mixed entity state round trips")
	if decoded.ok:
		check(bytes == Snapshot.encode(decoded.state), "Round trip is byte exact")
		decoded.state.enemies[0].timer = 11
		check(
			decoded.state.entities[2].timer == 11, "Restored compatibility view shares dictionaries"
		)
	var old := bytes.duplicate()
	old.encode_u32(8, 5)
	check(
		not Snapshot.decode(old, world.identity).ok, "Version five rejected before layout parsing"
	)
	var corrupt := bytes.duplicate()
	corrupt[Snapshot.HEADER] ^= 1
	check(not Snapshot.decode(corrupt, world.identity).ok, "Checksum corruption rejected")
	check(not Snapshot.decode(bytes.slice(0, -1), world.identity).ok, "Truncated checksum rejected")
	check(not Snapshot.decode(bytes, "wrong".sha256_text()).ok, "Wrong level identity rejected")
	corrupt = bytes.slice(0, -32)
	corrupt[44] ^= 1
	corrupt.append_array(Snapshot.checksum(corrupt))
	check(
		not Snapshot.decode(corrupt, world.identity).ok,
		"Schema mismatch rejected even with valid checksum"
	)
	corrupt = bytes.slice(0, -32)
	corrupt.encode_u32(Snapshot.count_offset(), 100001)
	corrupt.append_array(Snapshot.checksum(corrupt))
	check(not Snapshot.decode(corrupt, world.identity).ok, "Oversized entity count rejected")
	var other := world_for({"one": {"A": "o5", "X": 1, "Y": 2}})
	check(
		not Snapshot.decode(bytes, world.identity, other).ok,
		"Optional world validation checks full ordered table"
	)
	state.unlisted_scalar = 1
	check(not Snapshot.valid_state(state), "Undeclared scalar state cannot be silently omitted")
	state.erase("unlisted_scalar")
	state.entities[0].unlisted_scalar = 1
	check(not Snapshot.valid_state(state), "Undeclared entity state cannot be silently omitted")
	state.entities[0].erase("unlisted_scalar")
	state.entities[0].collected = 2
	check(not Snapshot.valid_state(state), "Collection flags must be binary")
	state.entities[0].collected = 0
	var stable_id: String = state.entities[0].id
	state.entities[0].id = state.entities[1].id
	check(not Snapshot.valid_state(state), "Duplicate stable ids rejected")
	state.entities[0].id = stable_id
	state.entities[1].squash = 13
	check(not Snapshot.valid_state(state), "Type validation rejects invalid pad state")
	state.entities[1].squash = 7
	state.entities[2].timer = 211
	check(not Snapshot.valid_state(state), "Actor validation retains timer bounds")
	state.entities[2].timer = 37
	state.captured_by = 1
	check(not Snapshot.valid_state(state), "Invalid capture target rejected")
	var empty := State.create(world_for())
	check(
		Snapshot.decode(Snapshot.encode(empty), empty.identity).ok, "Empty entity table round trips"
	)
	var objects := {}
	for code: String in Registry.codes():
		var options := {"A": code, "X": 1, "Y": 2, "E1": "32", "E2": "64"}
		options.merge(FIXTURE_OPTIONS.get(code, {}), true)
		objects["id_" + code + "_é"] = options
	var all_world := world_for(objects)
	var all_state := State.create(all_world)
	var all_bytes := Snapshot.encode(all_state)
	var all_decoded := Snapshot.decode(all_bytes, all_world.identity, all_world)
	check(
		all_decoded.ok and Snapshot.encode(all_decoded.state) == all_bytes,
		"Every type and UTF-8 stable id round trips"
	)


func lifecycle_checks() -> void:
	var world := world_for({"one": {"A": "e2", "X": 1000, "Y": 100, "M": 2}})
	var state := State.create(world)
	var actor: Dictionary = state.entities[0]
	Registry.advance(state, world, 0)
	check(actor.status == 0, "Offscreen actor waits in fixed activation area")
	state.camera_x = actor.x
	state.camera_y = actor.y
	state.x = actor.x + S
	Registry.advance(state, world, 0)
	check(actor.status == 1 and actor.cycles == -1, "Activation sets facing and flyer cycle")
	actor.collected = 1
	actor.checkpoint_collected = 1
	state.camera_x = actor.x + 900 * S
	Registry.advance(state, world, 0)
	check(
		actor.status == 2 and actor.offscreen == 1,
		"Distance queues respawn and records anchor leaving screen"
	)
	state.camera_x = 1000 * S
	state.camera_y = 100 * S
	Registry.advance(state, world, 0)
	check(actor.status == 1, "Returning anchor recreates and reactivates actor")
	check(
		actor.collected == 1 and actor.checkpoint_collected == 1,
		"Camera respawn preserves collection flags"
	)
	actor.status = 3
	Registry.advance(state, world, 0)
	check(actor.status == 3, "Defeated actor does not respawn")


func contact_checks() -> void:
	var world := world_for({"pad": {"A": "o11", "X": 100, "Y": 84, "F": 0}})
	var state := State.create(world)
	state.x = 100 * S
	state.y = 90 * S
	state.vy = S
	Registry.contact(state, 4, world)
	check(state.vy == -1216 * 60 and state.entities[0].squash == 12, "Pad held bounce is unchanged")
	world = world_for({"goal": {"A": "o5", "X": 100, "Y": 100}})
	state = State.create(world)
	state.x = 100 * S
	state.y = 100 * S
	Registry.contact(state, 0, world)
	check(
		state.goal_reached == 1 or state.get("life_phase", 0) != 0, "Goal type calls lifetime hook"
	)


func step_check() -> void:
	var world := mixed_world()
	var state := State.create(world)
	Sim.advance(state, 0, world)
	check(
		state.frame == 1 and state.entities.size() == 5, "Real pure tick uses the entity dispatch"
	)
	check(
		Snapshot.decode(Snapshot.encode(state), world.identity, world).ok,
		"One pure tick remains snapshot compatible"
	)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
