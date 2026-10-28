extends SceneTree
## Invented placements and controlled states only. No frames, recordings or devices.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	registration_checks()
	span_checks()
	turning_span_checks()
	switch_block_checks()
	snapshot_checks()
	print("S8_OBJECTS_B_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _level(objects: Dictionary) -> Dictionary:
	return {
		"version": "s3.8.0",
		"name": "Invented objects",
		"author": "Eggshell",
		"desc": "",
		"startpoint": {"map": 1, "X": 64, "Y": 100},
		"maps": {"map1": {"width": 4096, "height": 1024, "objects": objects}}
	}


func _build(objects: Dictionary) -> Dictionary:
	return World.build(JSON.stringify(_level(objects)), {"tilemaps": {}})


func _degrades(code: String, options: Dictionary) -> bool:
	var built := _build({"one": _place(code, 200, 200, options)})
	return built.ok and built.world.entities[0].code == "?" + code


func _world_for(objects: Dictionary) -> Dictionary:
	var built := _build(objects)
	check(built.ok, "Invented placements compile: " + str(built.get("error", "")))
	return built.get("world", {})


func _by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	check(false, "Expected placement exists: " + id)
	return {}


func _place(code: String, x: int, y: int, options: Dictionary = {}) -> Dictionary:
	var result := {"A": code, "X": x, "Y": y}
	result.merge(options, true)
	return result


func _land(state: Dictionary, world: Dictionary, x: int, y: int, ticks: int = 40) -> void:
	state.x = x
	state.y = y
	state.vx = 0
	state.vy = 0
	for _tick in ticks:
		Sim.advance(state, 0, world)


func registration_checks() -> void:
	for code: String in ["p6", "p9", "p10", "p13", "p11", "p12", "o30"]:
		check(Registry.implemented(code), "Slice 8 B code is registered: " + code)
	check(_degrades("o30", {"F": 2}), "An unknown switch colour becomes a placeholder")
	for pair: Array in [
		["o30", {"F": 0.5}], ["p9", {"E1": "wide"}], ["p11", {"E1": "-4"}], ["p13", {"E1": []}]
	]:
		var built := _build({"one": _place(pair[0], 200, 200, pair[1])})
		check(not built.ok, "Malformed option is rejected: " + pair[0])


func span_checks() -> void:
	var world := _world_for(
		{
			"log": _place("p9", 600, 300, {"E1": "160.9"}),
			"pipe": _place("p10", 1000, 300),
			"fort": _place("p13", 1400, 300, {"E1": "64"}),
			"cap": _place("p6", 1800, 300, {"E1": "96", "E2": "128"})
		}
	)
	var state := State.create(world)
	var type: Script = Registry.lookup("p9")
	check(type.SOLID == 2, "Resizable spans are top-only")
	check(
		type.solid_box(_by_id(state, "log")) == [520 * S, 284 * S, 680 * S, 286 * S],
		"The log span truncates its width and supports 12 px below its 56 px body top"
	)
	check(
		type.solid_box(_by_id(state, "pipe")) == [936 * S, 284 * S, 1064 * S, 286 * S],
		"A missing width keeps the 128 px default"
	)
	check(
		type.solid_box(_by_id(state, "fort")) == [1368 * S, 284 * S, 1432 * S, 286 * S],
		"The fort span supports at its body top"
	)
	check(
		type.solid_box(_by_id(state, "cap")) == [1752 * S, 284 * S, 1848 * S, 286 * S],
		"The cap span supports at its body top"
	)
	check(type.view_state(_by_id(state, "log"), state).size_y == 56.0, "The log span draws 56 px")
	_land(state, world, 600 * S, 260 * S)
	check(state.y <= 284 * S and state.y > 283 * S, "A falling player lands on the log span")
	state.x = 1000 * S
	state.y = 320 * S
	state.vy = -600 * 60
	Collision.begin_step(state, world, Registry)
	check(
		Collision.vertical(state, world, Sim.PLAYER_BOX, -40 * S) == -40 * S,
		"A rising player passes up through a span"
	)


func _spin_world() -> Dictionary:
	return _world_for(
		{
			"left": _place("p11", 600, 300, {"E1": "96", "E2": "1"}),
			"right": _place("p11", 900, 300, {"E1": "96"}),
			"other": _place("p12", 1200, 300, {"E1": "96"}),
			"switch": _place("o30", 600, 120),
			"switch1": _place("o30", 1500, 120, {"F": 1})
		}
	)


func turning_span_checks() -> void:
	var world := _spin_world()
	var state := State.create(world)
	var span := _by_id(state, "left")
	var type: Script = Registry.lookup("p11")
	check(type.SOLID == 1, "Turning spans are full solids")
	check(
		type.solid_box(span) == [548 * S, 284 * S, 652 * S, 308 * S],
		"The span body is E1 + 8 px wide and 24 px tall, centred 4 px above the span"
	)
	_land(state, world, 600 * S, 250 * S)
	check(state.y <= 284 * S and state.y > 283 * S, "A player stands on an idle span")
	type.start_turn(span)
	check(type.solid_box(span).is_empty(), "A turning span has no body")
	for _tick in 37:
		Sim.advance(state, 0, world)
	check(span.spin == 1 and span.flipped == 0, "The turn lasts 38 ticks")
	check(state.y > 290 * S, "A player on a turning span falls through")
	Sim.advance(state, 0, world)
	check(span.spin == 0 and span.flipped == 1, "A finished turn leaves the span flipped")
	check(not type.solid_box(span).is_empty(), "A flipped span is solid again")
	check(
		type.view_state(span, state).rotation == 180.0, "A flipped span draws turned half a circle"
	)
	span.spin = 30
	check(
		Registry.lookup("p12").view_state(_by_id(state, "other"), state).rotation == 0.0,
		"An idle span draws level"
	)


func switch_block_checks() -> void:
	var world := _spin_world()
	var state := State.create(world)
	var block := _by_id(state, "switch")
	var type: Script = Registry.lookup("o30")
	check(
		type.solid_box(block) == [584 * S, 104 * S, 616 * S, 136 * S], "The switch block is 32x32"
	)
	# Jump into the block from below.
	state.x = 600 * S
	state.y = 200 * S
	state.vy = -700 * 60
	state.on_floor = 0
	var struck := false
	for _tick in 20:
		Sim.advance(state, 0, world)
		struck = struck or block.busy > 0
	check(struck, "A head strike from below triggers the switch block")
	check(
		_by_id(state, "left").spin > 0 or _by_id(state, "left").flipped == 1,
		"The strike turns every span of the block's colour"
	)
	check(
		_by_id(state, "right").spin == _by_id(state, "left").spin,
		"Spans of one colour turn together"
	)
	check(
		_by_id(state, "other").spin == 0 and _by_id(state, "other").flipped == 0,
		"Spans of the other colour stay put"
	)
	state = State.create(world)
	block = _by_id(state, "switch")
	check(type.trigger(block, state, world), "A struck block with idle spans lifts")
	check(block.busy == 12, "The lift lasts 12 ticks")
	for tick in 6:
		type.step(block, state, world)
	check(block.y == block.home_y - 32 * S, "The block peaks 32 px up halfway through the lift")
	for tick in 6:
		type.step(block, state, world)
	check(block.y == block.home_y and block.busy == 0, "The block returns home")
	check(
		not type.trigger(block, state, world),
		"With every matching span still turning, the block does nothing"
	)
	var lone := _by_id(state, "switch1")
	check(
		type.trigger(lone, state, world) and _by_id(state, "other").spin > 0,
		"A colour 1 block turns colour 1 spans"
	)
	var bare_world := _world_for({"block": _place("o30", 300, 200)})
	var bare := State.create(bare_world)
	check(
		type.trigger(_by_id(bare, "block"), bare, bare_world),
		"With no span of its colour, the block still lifts"
	)
	state = State.create(world)
	block = _by_id(state, "switch")
	var egg := {"code": "o7", "x": 600 * S, "bounces": 3}
	check(type.projectile_contact(block, egg, state, world) == 1, "A thrown egg is consumed")
	check(block.busy == 12 and _by_id(state, "left").spin > 0, "A thrown egg triggers the block")
	check(
		type.projectile_contact(block, egg, state, world) == 3,
		"A lifting block reflects the next projectile as a solid"
	)


func snapshot_checks() -> void:
	var world := _spin_world()
	var state := State.create(world)
	type_trigger(state, world)
	for _tick in 5:
		Sim.advance(state, 0, world)
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(
		decoded.ok and Snapshot.encode(decoded.state) == bytes,
		"Turning spans and a lifting switch block round trip"
	)
	var spans := _world_for(
		{
			"a": _place("p6", 100, 100, {"E1": "64", "E2": "32"}),
			"b": _place("p9", 300, 100, {"E1": "64"}),
			"c": _place("p10", 500, 100, {"E1": "64"}),
			"d": _place("p13", 700, 100, {"E1": "64"})
		}
	)
	var span_state := State.create(spans)
	bytes = Snapshot.encode(span_state)
	decoded = Snapshot.decode(bytes, spans.identity, spans)
	check(decoded.ok and Snapshot.encode(decoded.state) == bytes, "Resizable spans round trip")


func type_trigger(state: Dictionary, world: Dictionary) -> void:
	Registry.lookup("o30").trigger(_by_id(state, "switch"), state, world)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
