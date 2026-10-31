extends SceneTree
## Oracle-only extractor. The candidate never loads this script or Godot.
const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const World = preload("res://src/sim/world.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
const Collision = preload("res://src/sim/collision.gd")
const Simulation = preload("res://src/sim/step.gd")
const SOURCE := "297ada9a022d0ddc297dd2d4091c5dccfab4531e"


func _initialize() -> void:
	call_deferred("run")


func fail(message: String) -> void:
	push_error(message)
	print("ORACLE_FAILED ", message)
	quit(1)


func write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", false, true))
	return true


func schema() -> Dictionary:
	var declarations := [
		"code-and-id-utf8", State.level_fields(), State.player_fields(), Registry.COMMON_FIELDS
	]
	var entities := []
	for code: String in Registry.codes():
		var fields := Registry.fields(code)
		declarations.append([code, fields])
		entities.append(
			{
				"code": code,
				"fields": fields,
				"dynamic": bool(Registry.constant(Registry.lookup(code), "DYNAMIC", false)),
				"enemy": Registry.is_enemy(code)
			}
		)
	return {
		"source_sha": SOURCE,
		"version": Snapshot.VERSION,
		"digest": Snapshot.schema_hash().hex_encode(),
		"digest_input": JSON.stringify(declarations),
		"level": State.level_fields(),
		"player": State.player_fields(),
		"common": Registry.COMMON_FIELDS,
		"entities": entities,
	}


func snapshot_into(file: FileAccess, state: Dictionary) -> bool:
	var bytes := Snapshot.encode(state)
	if bytes.is_empty():
		fail("Invalid oracle state: " + Snapshot.refusal(state))
		return false
	file.store_32(bytes.size())
	file.store_buffer(bytes)
	return true


# CLI validation guards must stop at the first failed boundary.
# gdlint: disable=max-returns
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		fail("usage: export.gd -- LEVEL_JSON INPUT_JSON OUT_DIR")
		return
	var level_path: String = args[0]
	var input_path: String = args[1]
	var out: String = args[2]
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		fail("Cannot create oracle output directory")
		return
	if not write_json(out.path_join("schema.json"), schema()):
		fail("Cannot write complete v10 schema")
		return
	var code := FileAccess.get_file_as_string(level_path)
	var decoded: Variant = JSON.parse_string(code)
	if decoded is String:
		code = decoded
	var built := World.build(code, CollisionTable.read())
	if not built.ok:
		fail("World: " + str(built))
		return
	var world: Dictionary = built.world
	var unsupported := []
	for map: Dictionary in world.maps.values():
		for source: Dictionary in map.entities:
			if source.has("placeholder"):
				unsupported.append(
					{"id": source.id, "code": source.code, "reason": source.placeholder}
				)
	if not unsupported.is_empty():
		write_json(out.path_join("unsupported.json"), unsupported)
		fail("Reference target contains unsupported placements")
		return
	var inputs: Variant = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if not inputs is Array:
		fail("Inputs must be an array")
		return
	for input: Variant in inputs:
		if (
			not (input is int or input is float)
			or input != floor(input)
			or input < 0
			or input > 255
		):
			fail("Input must be an eight-bit integer")
			return
	Collision.verify_index = true
	Collision.verify_failures = 0
	var state := State.create(world)
	var trace := FileAccess.open(out.path_join("snapshots.v10.stream"), FileAccess.WRITE)
	if trace == null or not snapshot_into(trace, state):
		fail("Cannot write initial snapshot")
		return
	var initial := Snapshot.encode(state)
	var initial_file := FileAccess.open(out.path_join("initial.v10"), FileAccess.WRITE)
	initial_file.store_buffer(initial)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(initial)
	var previous := Time.get_ticks_msec()
	var observed_codes := {}
	var activated := {}
	var max_rows: int = state.entities.size()
	var travel_min: int = state.x
	var travel_max: int = state.x
	var spawns := 0
	var serial: int = state.dynamic_serial
	var sample_rows := []
	for index in inputs.size():
		Simulation.advance(state, int(inputs[index]), world)
		if not snapshot_into(trace, state):
			return
		var bytes := Snapshot.encode(state)
		hash.update(bytes)
		travel_min = mini(travel_min, state.x)
		travel_max = maxi(travel_max, state.x)
		max_rows = maxi(max_rows, state.entities.size())
		spawns += state.dynamic_serial - serial
		serial = state.dynamic_serial
		for entity: Dictionary in state.entities:
			observed_codes[entity.code] = true
			if entity.status == 1:
				activated[entity.token] = true
		if index % 60 == 0 or index == inputs.size() - 1:
			sample_rows.append(
				{
					"tick": index + 1,
					"frame": state.frame,
					"x": state.x,
					"y": state.y,
					"hits": state.hits,
					"health": state.health,
					"coins": state.coins,
					"redcoins": state.redcoins,
					"flowers": state.flowers,
					"life_phase": state.life_phase,
					"dynamic_serial": state.dynamic_serial
				}
			)
			# The reference decoder must continue its own literal bytes without drift.
			var restored := Snapshot.decode(bytes, state.identity, world)
			if not restored.ok or Snapshot.encode(restored.state) != bytes:
				fail("Reference self restore failed at tick %d" % (index + 1))
				return
			state = restored.state
			# The step's collision context still points at the replaced state, whose frame no
			# longer advances, so collision._context would call it current on the next step
			# (Life.before_step would see the old step's entity solids). A run without this
			# self-restore never has that; drop it so the trace stays the uninterrupted run.
			world.erase("solids_step")
		var now := Time.get_ticks_msec()
		if now - previous >= 1000:
			trace.flush()
			print(
				(
					"ORACLE_PROGRESS tick=%d/%d frame=%d x=%d rows=%d"
					% [index + 1, inputs.size(), state.frame, state.x, state.entities.size()]
				)
			)
			previous = now
	trace.flush()
	trace.close()
	var final_bytes := Snapshot.encode(state)
	var final_file := FileAccess.open(out.path_join("finish.v10"), FileAccess.WRITE)
	final_file.store_buffer(final_bytes)
	var registry_script: Script = Registry
	var loops: Script = load("res://src/sim/dispatch_loops.gd")
	var collision_script: Script = Collision
	var world_script: Script = World
	var counters := {
		"nearby_queries": registry_script.get("spike_nearby_queries"),
		"successful_spawns": registry_script.get("spike_spawns"),
		"entity_steps": loops.get("spike_steps"),
		"entity_contacts": loops.get("spike_contacts"),
		"entity_steps_by_code": loops.get("spike_steps_by_code"),
		"solid_queries": collision_script.get("spike_solid_queries"),
		"terrain_queries": world_script.get("spike_terrain_queries"),
	}
	var report := {
		"source_sha": SOURCE,
		"level_identity": world.identity,
		"input_sha256": FileAccess.get_file_as_string(input_path).sha256_text(),
		"schema_digest": Snapshot.schema_hash().hex_encode(),
		"requested_ticks": inputs.size(),
		"final_frame": state.frame,
		"trace_sha256": hash.finish().hex_encode(),
		"query_index_failures": Collision.verify_failures,
		"codes_observed": observed_codes.keys(),
		"activated_tokens": activated.keys(),
		"runtime_spawns": spawns,
		"max_rows": max_rows,
		"traversal_units": travel_max - travel_min,
		"deaths": state.deaths,
		"hits": state.hits,
		"coins": state.coins,
		"redcoins": state.redcoins,
		"flowers": state.flowers,
		"goal_reached": state.goal_reached,
		"samples": sample_rows,
		"counters": counters,
		"godot_version": Engine.get_version_info(),
		"limits":
		(
			"Original Godot evidence only. No candidate parity or timing. "
			+ "Activated tokens include static rows. Null counters mean no overlay. "
			+ "Overlay counters include two initial ticks. Self restores are not A/B restores."
		),
	}
	write_json(out.path_join("report.json"), report)
	if Collision.verify_failures:
		fail("Ordered/live query verification failed")
		return
	print(
		(
			"ORACLE_DONE ticks=%d frame=%d spawns=%d travel_units=%d hash=%s"
			% [inputs.size(), state.frame, spawns, travel_max - travel_min, report.trace_sha256]
		)
	)
	quit(0)
