extends SceneTree
## Fast checks for the placeholder rule on invented placements. No scenes or assets.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const World = preload("res://src/sim/world.gd")
const Sim = preload("res://src/sim/step.gd")
const S := preload("res://src/sim/units.gd").SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	degrade_checks()
	malformed_checks()
	snapshot_checks()
	print("PLACEHOLDER_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func level(objects: Dictionary) -> String:
	return JSON.stringify(
		{
			"version": "s3.8.0",
			"name": "Placeholders",
			"author": "Eggshell",
			"desc": "",
			"startpoint": {"map": 1, "X": 64, "Y": 100},
			"maps": {"map1": {"width": 2048, "height": 1024, "objects": objects}}
		}
	)


func build(objects: Dictionary) -> Dictionary:
	return World.build(level(objects), {"tilemaps": {}})


func find(world: Dictionary, id: String) -> Dictionary:
	for source: Dictionary in world.entities:
		if source.id == id:
			return source
	return {}


func degrade_checks() -> void:
	var raw := {"A": "e1", "X": 300, "Y": 200, "F": 9, "M": 1, "E1": "kept"}
	var built := build({"walker": {"A": "e1", "X": 100, "Y": 200}, "odd": raw})
	check(built.ok, "An unbuilt enemy variant does not stop the level")
	if not built.ok:
		return
	var world: Dictionary = built.world
	var source := find(world, "odd")
	check(source.code == "?e1", "A degraded known code carries the placeholder marker")
	check(Registry.degraded(source), "The compiled placement reports it degraded")
	check(Registry.lookup(source.code) == Registry.Inert, "The placeholder dispatches as inert")
	check(
		source.properties == JSON.parse_string(JSON.stringify(raw)),
		"Raw placement properties are kept"
	)
	check(source.x == 300 * S and source.y == 200 * S, "Placement position is kept")
	check(source.placeholder == "enemy option F=9", "The reason names the unbuilt option")
	check(
		world.enemies.size() == 1 and world.enemies[0].id == "walker",
		"A placeholder never joins the enemy family"
	)
	var state := State.create(world)
	var entity: Dictionary = state.entities[source.source_index]
	check(
		entity.id == "odd" and entity.token == source.source_index + 1,
		"The placeholder keeps its id and token"
	)
	check(Registry.valid(entity), "Placeholder state is valid common state")
	var before := entity.duplicate()
	for _tick in 30:
		Sim.advance(state, 0, world)
	check(state.entities[source.source_index] == before, "A placeholder never acts")
	check(state.enemies.size() == 1, "The read view excludes the placeholder")

	built = build({"pad": {"A": "o11", "X": 100, "Y": 100, "F": 5}})
	check(
		built.ok and built.world.entities[0].code == "?o11" and built.world.springs.is_empty(),
		"An unbuilt pad variant degrades outside the pad family"
	)
	built = build({"thing": {"A": "neutral_unknown", "X": 100, "Y": 100, "F": 3}})
	check(
		(
			built.ok
			and built.world.entities[0].code == "neutral_unknown"
			and Registry.placeholder_reason(built.world.entities[0]) == "unregistered code"
			and not Registry.degraded(built.world.entities[0])
		),
		"An unregistered code keeps its code and records the reason"
	)
	built = build({"flower": {"A": "e3", "X": 100, "Y": 100, "F": 1}})
	check(
		built.ok and built.world.entities[0].code == "e3" and built.world.enemies.size() == 1,
		"The second flower appearance is a built form"
	)


func malformed_checks() -> void:
	for value: Variant in [0.5, -1, "1", [], null]:
		var built := build({"bad": {"A": "e1", "X": 100, "Y": 100, "F": value}})
		check(not built.ok, "Malformed enemy variant still fails: " + str(value))
	var built := build({"bad": {"A": "e1", "X": "left", "Y": 100}})
	check(not built.ok, "Malformed position still fails")
	built = build({"bad": {"A": "o11", "X": 100, "Y": 100, "F": 1.5}})
	check(not built.ok, "Malformed pad variant still fails")
	built = build({"bad": {"A": "p1", "X": 100, "Y": 100, "E1": "wide"}})
	check(not built.ok, "Malformed bridge width still fails")


func snapshot_checks() -> void:
	var built := build(
		{
			"walker": {"A": "e1", "X": 100, "Y": 200},
			"odd": {"A": "e2", "X": 300, "Y": 200, "F": 7},
			"goal": {"A": "o5", "X": 900, "Y": 200}
		}
	)
	check(built.ok, "A level with one placeholder loads")
	if not built.ok:
		return
	var world: Dictionary = built.world
	var state := State.create(world)
	for _tick in 10:
		Sim.advance(state, 0, world)
	var bytes := Snapshot.encode(state)
	check(not bytes.is_empty(), "A level with a placeholder saves")
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok, "A level with a placeholder restores")
	if not decoded.ok:
		return
	check(Snapshot.encode(decoded.state) == bytes, "The restored table is byte exact")
	var restored: Dictionary = decoded.state.entities[1]
	check(
		restored.code == "?e2" and restored.id == "odd" and restored.token == 2,
		"The restored placeholder keeps code, id and token"
	)
	check(decoded.state.enemies.size() == 1, "The restored read view excludes the placeholder")
