extends SceneTree
## Invented placements and controlled states only. No frames, recordings or devices.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Hits = preload("res://src/sim/hits.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	_check_solid_index()
	_registration_checks()
	_span_checks()
	_turning_span_checks()
	_switch_block_checks()
	_wheel_checks()
	_dice_checks()
	_egg_block_checks()
	_melon_checks()
	_balloon_checks()
	_spike_checks()
	_snapshot_checks()
	print("S8_OBJECTS_B_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## With the solid index present, every query is checked against a full scan.
func _check_solid_index() -> void:
	var collision: Script = Collision
	if "verify_index" in collision:
		collision.set("verify_index", true)


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


func _registration_checks() -> void:
	for code: String in [
		"o30",
		"o21",
		"p6",
		"p7",
		"p8",
		"p9",
		"p10",
		"p11",
		"p12",
		"p13",
		"p14",
		"p15",
		"p16",
		"p17",
		"p18",
		"p19",
		"p20",
		"p21",
		"e12",
		"e13",
		"e17",
		"e19",
		"e23",
		"e24",
		"e29",
		"e33",
		"e35",
		"e37",
		"o25",
		"o27",
		"o33",
		"o34"
	]:
		check(Registry.implemented(code), "Slice 8 B code is registered: " + code)
	check(_degrades("o30", {"F": 2}), "An unknown switch colour becomes a placeholder")
	for pair: Array in [
		["o30", {"F": 0.5}], ["p9", {"E1": "wide"}], ["p11", {"E1": "-4"}], ["p13", {"E1": []}]
	]:
		var built := _build({"one": _place(pair[0], 200, 200, pair[1])})
		check(not built.ok, "Malformed option is rejected: " + pair[0])


func _span_checks() -> void:
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
	for code: String in ["p7", "p8", "p14", "p15", "p16", "p17", "p18", "p20", "p21"]:
		var one := _world_for({"span": _place(code, 300, 300)})
		var span := _by_id(State.create(one), "span")
		check(
			type.solid_box(span) == [252 * S, 284 * S, 348 * S, 286 * S],
			"A plain 96 px span supports at its top: " + code
		)
	var narrow := _world_for({"span": _place("p19", 300, 300)})
	check(
		_by_id(State.create(narrow), "span").width == 64 * S,
		"The narrow snow span defaults to 64 px"
	)
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


func _turning_span_checks() -> void:
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


func _switch_block_checks() -> void:
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


func _ride(state: Dictionary, world: Dictionary, ticks: int) -> void:
	for _tick in ticks:
		Sim.advance(state, 0, world)


func _wheel_checks() -> void:
	var world := _world_for(
		{
			"wheel": _place("o21", 400, 300, {"E1": "0", "E2": "120", "E3": "0", "R": 90}),
			"wall": _place("o28", 640, 300),
			"turner": _place("o21", 1200, 300, {"E1": "90", "E2": "64"}),
			"timed": _place("o21", 2000, 300, {"E2": "60", "E3": "0.5", "R": 0})
		}
	)
	var state := State.create(world)
	var type: Script = Registry.lookup("o21")
	var wheel := _by_id(state, "wheel")
	check(wheel.angle == 0 and wheel.speed == 120, "R 90 points the arrow right at E2 px/s")
	check(_by_id(state, "turner").angle == 270 * 60000, "A missing R points the arrow up")
	check(type.SOLID == 2, "The wheel deck is top-only")
	_land(state, world, 400 * S, 260 * S, 2)
	check(wheel.status == Registry.ACTIVE, "The wheel activates on screen")
	check(type.solid_box(wheel) == [378 * S, 278 * S, 422 * S, 280 * S], "The deck is 44 px wide")
	_ride(state, world, 30)
	check(wheel.riding == 1, "Standing on the deck starts the ride")
	check(wheel.x > 400 * S, "A riding wheel travels along its arrow")
	check(absi(state.x - wheel.x) < 2 * S, "The rider is carried with the wheel")
	var before: int = wheel.x
	_ride(state, world, 120)
	check(wheel.x < 640 * S - 63 * S, "The wheel never enters the solid in its path")
	check(wheel.angle == 180 * 60000 and wheel.x < before + 160 * S, "A blocked wheel reflects")
	state.x = 1000 * S
	state.y = 600 * S
	state.on_floor = 0
	Sim.advance(state, 0, world)
	check(wheel.riding == 0, "The ride stops when the rider falls below the deck")
	var resting: int = wheel.x
	Sim.advance(state, 0, world)
	check(wheel.x == resting, "A wheel without a rider stays put")
	var turner := _by_id(state, "turner")
	turner.status = Registry.ACTIVE
	var angle: int = turner.angle
	type.step(turner, state, world)
	check(turner.angle == angle + 90 * 1000, "An idle wheel turns E1 degrees per second")
	var timed := _by_id(state, "timed")
	timed.status = Registry.ACTIVE
	check(timed.life == 30, "E3 is the lifetime in seconds")
	timed.start = 1
	for _tick in 30:
		type.step(timed, state, world)
	check(timed.shrink == 1 and type.solid_box(timed).is_empty(), "An expired wheel shrinks")
	for _tick in 6:
		type.step(timed, state, world)
	check(timed.status == Registry.QUEUED, "A vanished wheel waits for camera respawn")


func _ledge_world(extra: Dictionary) -> Dictionary:
	var objects := {"floor": _place("p2", 500, 316, {"E1": "320"})}
	objects.merge(extra, true)
	return _world_for(objects)


func _activate(entity: Dictionary) -> void:
	entity.status = Registry.ACTIVE
	entity.started = 1


func _dice_checks() -> void:
	var world := _world_for(
		{
			"switch": _place("o33", 300, 120, {"E1": "255", "E2": "0", "E3": "0", "E4": "1"}),
			"solid": _place("o34", 400, 200, {"E4": "1", "F": 1}),
			"outline": _place("o34", 432, 200, {"E4": "1"}),
			"other": _place("o34", 600, 200, {"E4": "2", "F": 1})
		}
	)
	var state := State.create(world)
	state.x = 900 * S
	state.y = 500 * S
	var type: Script = Registry.lookup("o34")
	var solid := _by_id(state, "solid")
	var outline := _by_id(state, "outline")
	check(not type.solid_box(solid).is_empty(), "F 1 starts as a solid dice block")
	check(type.solid_box(outline).is_empty(), "A missing F starts as a passable outline")
	var switch := _by_id(state, "switch")
	check(type.trigger(switch, state, world), "A struck switch toggles its group")
	check(type.solid_box(solid).is_empty(), "The solid block becomes an outline")
	check(not type.solid_box(outline).is_empty(), "The outline becomes solid")
	check(not type.solid_box(_by_id(state, "other")).is_empty(), "Other groups stay put")
	check(switch.on == 1 and switch.busy == 12, "The switch shows its toggled face and lifts")
	check(not type.trigger(switch, state, world), "A lifting switch ignores another strike")
	for _tick in 12:
		type.step(switch, state, world)
	state.x = 400 * S
	state.y = 210 * S
	check(type.trigger(switch, state, world), "A returned switch can be struck again")
	check(
		type.solid_box(solid).is_empty() and solid.on == 0,
		"A block that turns solid under the player waits for the player to leave"
	)
	state.x = 900 * S
	type.step(solid, state, world)
	check(not type.solid_box(solid).is_empty(), "Once the player leaves, it is solid")
	var egg := {"code": "o7", "x": 300 * S}
	for _tick in 12:
		type.step(switch, state, world)
	check(type.projectile_contact(switch, egg, state, world) == 1, "An egg on a switch is consumed")
	check(outline.on == 0 and solid.on == 1, "An egg strike toggles the group")
	check(type.projectile_contact(solid, egg, state, world) == 0, "Eggs pass through outlines")
	check(_degrades("o34", {"F": 2}), "An unknown dice block form becomes a placeholder")


func _egg_block_checks() -> void:
	var world := _world_for(
		{"yellow": _place("o27", 300, 120), "red": _place("o27", 600, 120, {"F": 1})}
	)
	var state := State.create(world)
	var type: Script = Registry.lookup("o27")
	var yellow := _by_id(state, "yellow")
	check(type.solid_box(yellow) == [284 * S, 104 * S, 316 * S, 136 * S], "The egg block is 32x32")
	state.x = 300 * S
	state.y = 200 * S
	state.vy = -700 * 60
	state.on_floor = 0
	var struck := false
	for _tick in 20:
		Sim.advance(state, 0, world)
		struck = struck or yellow.busy > 0
	check(struck, "A head strike starts the egg block")
	check(type.solid_box(yellow).is_empty(), "A struck egg block is no longer solid")
	state.x = 900 * S  # Away, so the player does not collect the egg at once.
	state.y = 600 * S
	for _tick in 30:
		Sim.advance(state, 0, world)
	check(yellow.status == Registry.DEFEATED, "The struck block is gone after its rise and fall")
	var eggs: Array = state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "o7"
	)
	check(eggs.size() == 1, "It leaves one egg")
	if eggs.size() == 1:
		check(
			eggs[0].colour == 1 and eggs[0].floating == 1,
			"A plain block leaves a floating yellow egg"
		)
		check(eggs[0].x == yellow.x and eggs[0].y == yellow.home_y, "The egg appears in its place")
	var red := _by_id(state, "red")
	type.bump(red, state, world, 0)
	for _tick in 6:
		type.step(red, state, world)
	check(red.y == red.home_y - 64 * S * 6 / 15, "The block rises 64 px over 15 ticks")
	for _tick in 24:
		type.step(red, state, world)
	var reds: Array = state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "o7" and entity.colour == 2
	)
	check(reds.size() == 1, "F 1 leaves a red egg")
	check(_degrades("o27", {"F": 2}), "An unknown egg block colour becomes a placeholder")


func _melon_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 1000, 316, {"E1": "2000"}),
			"melon": _place("o25", 450, 284),
			"target": _place("e23", 700, 284)
		}
	)
	var state := State.create(world)
	state.x = 400 * S
	state.y = 300 * S - S / 16
	state.facing = 1
	var melon := _by_id(state, "melon")
	var target := _by_id(state, "target")
	for _tick in 3:
		Sim.advance(state, 0, world)
	check(melon.status == Registry.ACTIVE, "The melon activates on screen")
	Sim.advance(state, Moves.InputBits.USE, world)
	for _tick in 30:
		Sim.advance(state, 0, world)
	check(melon.status == Registry.DEFEATED, "The tongue eats the melon")
	check(
		state.move_ammo == Moves.SEED and state.move_ammo_count == 30,
		"A plain melon loads 30 seeds"
	)
	var seen_seed := false
	for _tick in 40:
		Sim.advance(state, Moves.InputBits.USE, world)
		seen_seed = (
			seen_seed
			or state.entities.any(
				func(entity: Dictionary) -> bool: return entity.code == "seed_shot"
			)
		)
	check(seen_seed, "Holding use spits seeds")
	check(state.move_ammo_count < 30, "Spitting spends seeds")
	check(target.status == Registry.DEFEATED, "A seed defeats the walker in its path")
	check(_degrades("o25", {"F": 3}), "A fire melon is not built yet and becomes a placeholder")
	check(_degrades("o25", {"F": 6}), "An ice melon is not built yet and becomes a placeholder")


func _balloon_checks() -> void:
	var world := _world_for(
		{
			"riser": _place("o26", 300, 500, {"E1": "96", "E2": "0", "E3": "0", "E4": "4", "F": 1}),
			"drifter": _place("o26", 700, 500, {"E1": "0", "E2": "128", "E3": "0", "E4": "1"}),
			"bobber": _place("o26", 1100, 500, {"E1": "0", "E2": "0", "E3": "1", "E4": "1"})
		}
	)
	var state := State.create(world)
	state.x = 2000 * S
	state.y = 100 * S
	var type: Script = Registry.lookup("o26")
	var riser := _by_id(state, "riser")
	var drifter := _by_id(state, "drifter")
	var bobber := _by_id(state, "bobber")
	for entity: Dictionary in [riser, drifter, bobber]:
		entity.status = Registry.ACTIVE
	check(
		type.solid_box(riser) == [270 * S, 480 * S, 330 * S, 482 * S],
		"The deck is 60 px wide, 20 px up"
	)
	type.step(riser, state, world)
	type.step(drifter, state, world)
	check(riser.y == 500 * S - 96 * 60, "E1 is the rise speed")
	check(drifter.x == 700 * S + 128 * 60, "E2 is the drift speed")
	for _tick in 15:
		type.step(bobber, state, world)
	check(bobber.y == 500 * S + 32 * S, "E3 bobs 32 px per unit over an E4 second period")
	state.x = riser.x
	state.y = riser.y - 20 * S
	state.on_floor = 1
	type.contact(riser, state, world, 0)
	check(riser.stepped == 1 and riser.land_delay == 6, "Landing pauses it")
	var before: int = riser.y
	for _tick in 6:
		type.step(riser, state, world)
	check(riser.y == before, "It holds still for the landing pause")
	type.step(riser, state, world)
	check(riser.y == before - 96 * 60 / 5, "Ridden, it rises at a fifth of its speed")
	state.y = 900 * S
	type.contact(riser, state, world, 0)
	check(riser.stepped == 0, "Leaving the deck restores its speed")


func _spike_checks() -> void:
	var world := _world_for(
		{
			"up": _place("o13", 300, 300),
			"down": _place("o13", 600, 300, {"R": 180}),
			"right": _place("o13", 900, 300, {"R": 90})
		}
	)
	var state := State.create(world)
	var type: Script = Registry.lookup("o13")
	var up := _by_id(state, "up")
	check(
		type.solid_box(up) == [284 * S, 284 * S, 316 * S, 316 * S], "The spike block is 32x32 solid"
	)
	check(type.spike_box(up) == [284 * S, 283 * S, 316 * S, 285 * S], "The spike edge is on top")
	check(
		type.spike_box(_by_id(state, "down")) == [584 * S, 315 * S, 616 * S, 317 * S],
		"R 180 puts the spike underneath"
	)
	check(
		type.spike_box(_by_id(state, "right")) == [915 * S, 284 * S, 917 * S, 316 * S],
		"R 90 puts the spike on the right"
	)
	state.x = 300 * S
	state.y = 284 * S
	type.contact(up, state, world, 0)
	check(state.life_phase == Life.DEAD, "Standing on the spike is fatal")
	state = State.create(world)
	state.x = 640 * S
	state.y = 300 * S
	type.contact(_by_id(state, "down"), state, world, 0)
	check(state.life_phase == Life.PLAY, "A safe face is harmless")
	check(_degrades("o13", {"R": 45}), "A diagonal spike becomes a placeholder")
	var blank_world := _world_for({"blank": _place("empty", 300, 300, {"E1": "64"})})
	var blank := _by_id(State.create(blank_world), "blank")
	check(
		blank.code == "empty" and not Registry.lookup("empty").view_state(blank, {}).visible,
		"An editor blank loads as nothing"
	)


func _snapshot_checks() -> void:
	var world := _spin_world()
	var state := State.create(world)
	_type_trigger(state, world)
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


func _type_trigger(state: Dictionary, world: Dictionary) -> void:
	Registry.lookup("o30").trigger(_by_id(state, "switch"), state, world)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
