extends SceneTree
## Invented placements and controlled states only. No frames, recordings or devices.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Life = preload("res://src/sim/life.gd")
const Hits = preload("res://src/sim/hits.gd")
const Effects = preload("res://src/view/map_effects.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	gradient_checks()
	ledge_checks()
	countdown_checks()
	flower_checks()
	flyer_checks()
	thief_checks()
	snapshot_checks()
	print("S8_OBJECTS_A_RESULT: %d assertions, %d failures" % [checks, failures])
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


func _stand(state: Dictionary, top: int, x: int) -> void:
	state.x = x
	state.y = top - S / 16
	state.vx = 0
	state.vy = 0
	state.on_floor = 1


func _floor_world(extra: Dictionary) -> Dictionary:
	var objects := {"floor": _place("p4", 1000, 316, {"E1": "1600"})}
	objects.merge(extra, true)
	return _world_for(objects)


func _near(a: Color, r: int, g: int, b: int) -> bool:
	return absf(a.r * 255 - r) < 0.01 and absf(a.g * 255 - g) < 0.01 and absf(a.b * 255 - b) < 0.01


func gradient_checks() -> void:
	check(Effects.custom_gradient(null).is_empty(), "No generated gradient without the field")
	check(Effects.custom_gradient("32|0").is_empty(), "A short field is ignored")
	var plan := Effects.custom_gradient("4|0|448|0,0,0_80,160,240")
	var bands: Array = plan.bands
	check(bands.size() == 4, "Lines split evenly between two colours")
	check(bands[0].y == 0.0 and bands[1].y == 112.0, "Bands step by (end - start) / lines")
	check(bands[0].height == 113.0, "Each band overlaps the next by one row")
	check(_near(bands[0].color, 0, 0, 0), "The first band uses the first colour")
	check(_near(bands[2].color, 40, 80, 120), "Middle bands interpolate in steps of 8")
	check(_near(plan.fill, 80, 160, 240), "Everything else uses the last colour")
	var offset := Effects.custom_gradient("2|50|250|300,-5,7 _10,10,10")
	check(offset.bands[0].y == 0.0 and offset.bands[0].height == 51.0, "A low start fills above")
	check(_near(offset.bands[0].color, 255, 0, 7), "Channels clamp to the byte range")
	var three := Effects.custom_gradient("6|0|600|0,0,0_0,0,240_0,0,0")
	check(three.bands.size() == 6, "Each segment gets its share of the lines")
	check(_near(three.bands[3].color, 0, 0, 240), "The second segment starts at its colour")
	check(Effects.custom_gradient("8|0|448|9,9,9").bands.is_empty(), "One colour draws no bands")


func ledge_checks() -> void:
	var world := _world_for(
		{
			"castle": _place("p4", 300, 300, {"E1": "128"}),
			"cap": _place("p5", 600, 300, {"E1": "96", "E2": "64"}),
			"plain": _place("p5", 900, 300)
		}
	)
	var state := State.create(world)
	var castle := _by_id(state, "castle")
	var cap := _by_id(state, "cap")
	var type: Script = Registry.lookup("p4")
	check(type.SOLID == 2 and Registry.lookup("p5") == type, "Both ledges are top-only")
	check(type.solid_box(castle) == [236 * S, 284 * S, 364 * S, 286 * S], "E1 sets the width")
	check(cap.stalk == 64 * S and _by_id(state, "plain").stalk == 0, "E2 sets the stalk height")
	check(not _build({"one": _place("p5", 1, 1, {"E2": [1]})}).ok, "A malformed stalk is refused")
	state.x = 300 * S
	state.y = 270 * S
	for tick in 30:
		Sim.advance(state, 0, world)
	check(state.y <= 284 * S and state.y > 283 * S, "A falling player lands on the ledge")


func countdown_checks() -> void:
	var world := _floor_world({"count": _place("o32", 600, 268, {"F": 1})})
	var state := State.create(world)
	var ledge := _by_id(state, "count")
	var type: Script = Registry.lookup("o32")
	check(ledge.count == 2, "The form plus one is the starting number")
	check(type.solid_box(ledge) == [568 * S, 242 * S, 632 * S, 244 * S], "Its top strip is 64 px")
	check(_degrades("o32", {"F": 120}), "An oversized number degrades")
	for round in 2:
		_stand(state, 242 * S, 600 * S)
		Sim.advance(state, 0, world)
		check(ledge.pressed == 1, "Standing on it presses it")
		state.x = 900 * S
		state.y = 300 * S - S / 16
		Sim.advance(state, 0, world)
	check(ledge.status == Registry.DEFEATED, "Stepping off at one breaks it")
	world = _floor_world({"count": _place("o32", 600, 268, {"F": 3}), "w": _place("e7", 600, 220)})
	state = State.create(world)
	state.x = 900 * S
	state.y = 300 * S - S / 16
	ledge = _by_id(state, "count")
	var pressed := false
	for tick in 60:
		Sim.advance(state, 0, world)
		pressed = pressed or ledge.pressed == 1
	check(pressed, "An enemy standing on it also presses it")
	check(type.valid(ledge), "Countdown state stays valid")


func flower_checks() -> void:
	var world := _floor_world({"flower": _place("o22", 600, 252, {"E1": "2"})})
	var state := State.create(world)
	state.x = 700 * S
	state.y = 300 * S - S / 16
	var flower := _by_id(state, "flower")
	var type: Script = Registry.lookup("o22")
	check(flower.stars == 2, "E1 sets the number of releases")
	for tick in 3:
		Sim.advance(state, 0, world)
	check(flower.status == Registry.ACTIVE, "The flower activates near the player")
	var spat := Registry.spawn_dynamic(state, world, "e7", 600 * S, 230 * S, {})
	spat.status = 1
	spat.spat = 1
	Sim.advance(state, 0, world)
	check(spat.status == Registry.DEFEATED and flower.phase == type.FED, "A spat body is swallowed")
	check(flower.collected == 1 and flower.can_despawn == 0, "A fed flower stays and is recorded")
	var seen := {}
	state.x = 900 * S
	for tick in 200:
		Sim.advance(state, 0, world)
		for entity: Dictionary in state.entities:
			if entity.code in ["o4", "o1"] and entity.source_index == -1:
				seen[entity.id] = true
	var released := seen.size()
	check(released == 2, "It releases one pickup per star")
	for tick in 140:
		Sim.advance(state, 0, world)
	check(flower.status == Registry.DEFEATED, "It wilts after the last star")
	state = State.create(world)
	flower = _by_id(state, "flower")
	flower.status = 1
	var egg := {"code": "o7", "x": flower.x - 10 * S, "y": flower.y + 10 * S, "mode": 1}
	check(type.projectile_contact(flower, egg, state, world) == 2, "A thrown egg is caught")
	check(
		egg.mode == 0 and egg.vx == -384 * 60 and egg.vy == -384 * 60, "It drops as a resting egg"
	)
	check(type.valid(flower), "Flower state stays valid")


func flyer_checks() -> void:
	var cells := []
	for index in 64:
		cells.append(0 if index < 8 else -1)
	var world := _world_for(
		{"hang": _place("e14", 100, 48, {"M": 1}), "fly": _place("e14", 400, 100, {"F": 1})}
	)
	world.layers = [_tile_layer("roof", cells, 8, [0, 0, 32, 0, 32, 32, 0, 32])]
	var state := State.create(world)
	var hang := _by_id(state, "hang")
	var fly := _by_id(state, "fly")
	var type: Script = Registry.lookup("e14")
	for entity: Dictionary in [hang, fly]:
		entity.status = 1
	state.x = 2000 * S
	state.y = 600 * S
	type.step(hang, state, world)
	type.step(fly, state, world)
	check(hang.mode == type.HANG, "A flyer under a ceiling hangs")
	check(fly.mode == type.FORWARD and fly.x == 400 * S - 128 * 60, "The second form flies at 128")
	state.x = 200 * S
	state.y = 300 * S
	type.step(hang, state, world)
	check(hang.mode == type.DIVE and hang.facing == 1, "A player below within 248 px starts a dive")
	var y0: int = hang.y
	type.step(hang, state, world)
	check(hang.y - y0 == 128 * 60, "The dive falls at 128 px/s")
	while hang.mode == type.DIVE:
		type.step(hang, state, world)
	check(hang.mode == type.SWOOP, "Near the player's height it swoops")
	for tick in type.SWOOP_TICKS:
		type.step(hang, state, world)
	check(hang.mode == type.FORWARD and hang.y == hang.target_y, "The loop ends where it began")
	state.x = fly.x
	state.y = fly.y + 40 * S
	state.invulnerable = 0
	type.contact(fly, state, world, 0)
	check(state.invulnerable > 0, "Touching it from below hurts")
	state.x = fly.x
	state.y = fly.y - 2 * S
	state.vy = 3 * S
	fly.contact = 0
	type.contact(fly, state, world, 0)
	check(fly.status == Registry.DEFEATED and state.vy < 0, "A stomp defeats it and bounces")
	check(type.valid(hang), "Flyer state stays valid")


func thief_checks() -> void:
	var world := _floor_world({"thief": _place("e10", 600, 284, {"M": 1})})
	var state := State.create(world)
	state.x = 990 * S
	state.y = 300 * S - S / 16
	var thief := _by_id(state, "thief")
	var type: Script = Registry.lookup("e10")
	var idled := false
	var turned := false
	for tick in 400:
		Sim.advance(state, 0, world)
		idled = idled or thief.pose == type.IDLE
		turned = turned or thief.facing < 0
	check(thief.status == 1 and idled and turned, "It patrols, rests and turns back")
	check(absi(thief.x - 600 * S) <= 140 * S, "It patrols near its start")
	state.x = thief.x + 150 * S
	Sim.advance(state, 0, world)
	check(thief.plan == type.CHASE and thief.vy < 0, "A near player starts a chase with a hop")
	state = State.create(world)
	thief = _by_id(state, "thief")
	thief.status = 1
	thief.started = 1
	state.x = thief.x + 10 * S
	state.y = thief.y + 16 * S
	type.contact(thief, state, world, 0)
	check(
		state.separated == 1 and state.companion_mode == Life.BUBBLE, "A touch takes the companion"
	)
	check(thief.carrying == 1 and thief.plan == type.EVADE, "The thief carries the bubble away")
	Collision.begin_step(state, world, Registry)
	type.step(thief, state, world)
	check(state.recovery_x == thief.x, "The bubble rides on the thief")
	state = State.create(world)
	thief = _by_id(state, "thief")
	thief.status = 1
	thief.started = 1
	for round in 3:
		state.x = thief.x
		state.y = thief.y - 2 * S
		state.vy = 3 * S
		thief.contact = 0
		thief.vy = 0
		type.contact(thief, state, world, 0)
	check(thief.status == Registry.DEFEATED, "Three stomps defeat it")
	var coins := 0
	for entity: Dictionary in state.entities:
		if entity.code == "o1" and entity.source_index == -1:
			coins += 1
	check(coins == 3, "A defeated thief drops three coins")
	state = State.create(world)
	thief = _by_id(state, "thief")
	thief.status = 1
	var egg := {"code": "o7", "x": thief.x - 20 * S, "fall_on_terrain": 0}
	check(type.projectile_contact(thief, egg, state, world) == 1, "An egg is used up")
	check(thief.hit_health == 5 and thief.vx > 0, "It takes a hit and is knocked away")
	check(type.tongue(thief, state, world) == 2, "The tongue bounces off")
	for hit in 5:
		type.projectile_contact(thief, egg, state, world)
	check(thief.status == Registry.DEFEATED, "Six strikes defeat it")
	check(type.valid(_by_id(State.create(world), "thief")), "Thief state is valid")


func _tile_layer(name: String, cells: Array, columns: int, points: Array) -> Dictionary:
	var polygon := PackedInt64Array()
	for value: int in points:
		polygon.append(value * S)
	return {
		"name": name,
		"layer": "layer1",
		"slot": [1, 0],
		"size": 32,
		"width": columns,
		"height": cells.size() / columns,
		"cells": cells,
		"bounds": {0: [0, 0, 32 * S, 32 * S]},
		"polygons": {0: polygon},
		"solid": true,
		"water": false
	}


func snapshot_checks() -> void:
	var world := _world_for(
		{
			"a": _place("p4", 100, 100, {"E1": "64.00000000000728"}),
			"b": _place("p5", 200, 100, {"E1": "96", "E2": "128"}),
			"c": _place("o32", 300, 100, {"F": 8}),
			"d": _place("o22", 400, 100, {"E1": "8"}),
			"e": _place("e14", 500, 100, {"F": 1, "M": 2}),
			"f": _place("e10", 600, 100, {"M": 2})
		}
	)
	var state := State.create(world)
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok and Snapshot.encode(decoded.state) == bytes, "Slice 8 objects round trip")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
