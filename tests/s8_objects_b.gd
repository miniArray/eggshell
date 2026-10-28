extends SceneTree
## Invented placements and controlled states only. No frames, recordings or devices.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Hits = preload("res://src/sim/hits.gd")
const Moves = preload("res://src/sim/moves.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	registration_checks()
	span_checks()
	turning_span_checks()
	switch_block_checks()
	wheel_checks()
	soft_walker_checks()
	soft_giant_checks()
	gust_checks()
	dice_checks()
	egg_block_checks()
	spore_checks()
	launcher_checks()
	shot_checks()
	melon_checks()
	leaper_checks()
	bumper_checks()
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
	for code: String in [
		"p6", "p9", "p10", "p13", "p11", "p12", "o30", "o21", "e23", "e24", "e33", "o33", "o34"
	]:
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


func _ride(state: Dictionary, world: Dictionary, ticks: int) -> void:
	for _tick in ticks:
		Sim.advance(state, 0, world)


func wheel_checks() -> void:
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


func soft_walker_checks() -> void:
	var world := _ledge_world({"milde": _place("e23", 400, 284)})
	var state := State.create(world)
	state.x = 900 * S
	state.y = 100 * S
	var milde := _by_id(state, "milde")
	var type: Script = Registry.lookup("e23")
	_activate(milde)
	Sim.advance(state, 0, world)
	check(milde.vx == -48 * 60, "The soft walker walks left at 48 px/s")
	check(absi(milde.y - 284 * S) < S, "The soft walker stands on the span")
	for _tick in 120:
		Sim.advance(state, 0, world)
	check(milde.facing == 1 and milde.x > 340 * S, "The soft walker turns at the ledge")
	state.x = milde.x
	state.y = milde.y - 10 * S
	type.contact(milde, state, world, 0)
	check(milde.mode == type.SQUASH, "Landing on the soft walker squashes it")
	check(state.y == milde.y and state.vy == 0, "The squashed walker holds the player on top")
	for _tick in 15:
		type.step(milde, state, world)
	check(milde.status == Registry.DEFEATED, "The squashed walker bursts after 15 ticks")
	state = State.create(world)
	milde = _by_id(state, "milde")
	_activate(milde)
	state.x = milde.x - 10 * S
	state.y = milde.y + 16 * S
	type.contact(milde, state, world, 0)
	check(state.invulnerable > 0 and milde.status == Registry.ACTIVE, "Side contact hurts")
	var egg := {"code": "o7", "x": milde.x, "fall_on_terrain": 0}
	check(type.projectile_contact(milde, egg, state, world) == 3, "An egg passes through")
	check(milde.status == Registry.DEFEATED, "An egg defeats the soft walker")


func soft_giant_checks() -> void:
	var world := _ledge_world({"big": _place("e24", 500, 268)})
	var state := State.create(world)
	var big := _by_id(state, "big")
	var type: Script = Registry.lookup("e24")
	check(big.y == 300 * S, "The large walker stands on its placement's lower edge")
	_activate(big)
	for _tick in 6:
		type.step(big, state, world)
	check(big.mode == type.WALK and big.vx == -48 * 60, "It starts walking after a short wait")
	state.x = big.x
	state.y = big.y - 50 * S
	state.vy = 300 * 60
	type.contact(big, state, world, 0)
	check(state.vy < 0 and big.mode == type.PAUSE, "A plain landing bounces and stalls it")
	for _tick in 31:
		type.step(big, state, world)
	check(big.mode == type.WAIT, "The stall ends in the short wait")
	big.contact = 0
	state.y = big.y - 50 * S
	state.move_action = Moves.POUND_FALL
	type.contact(big, state, world, 0)
	check(big.mode == type.SQUASH, "A ground pound squashes it")
	for _tick in 15:
		type.step(big, state, world)
	check(big.status == Registry.DEFEATED, "The squashed walker bursts")
	var copies: Array = state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "e23"
	)
	check(copies.size() == 4, "The burst throws out four small walkers")
	if copies.size() == 4:
		check(
			copies[0].mode == 2 and copies[0].facing == -1 and copies[3].facing == 1,
			"The copies tumble outward"
		)
		check(copies[1].vy == -480 * 60, "The inner copies launch at 480 px/s")
	state = State.create(world)
	big = _by_id(state, "big")
	_activate(big)
	var egg := {"code": "o7", "x": big.x - 20 * S, "vx": 300 * 60, "fall_on_terrain": 0}
	check(type.projectile_contact(big, egg, state, world) == 1, "An egg is consumed")
	check(
		big.slide_ticks == 48 and big.slide_from == 512 * 60 and big.status == Registry.ACTIVE,
		"An egg shoves it along the egg's travel instead of defeating it"
	)
	state.x = big.x + 20 * S
	state.y = big.y
	state.move_action = 0
	big.contact = 0
	type.contact(big, state, world, 0)
	check(state.invulnerable > 0, "Side contact with the large walker hurts")


func gust_checks() -> void:
	var world := _world_for(
		{
			"left": _place("e33", 600, 200, {"R": 270}),
			"right": _place("e33", 600, 400, {"R": 90}),
			"seek": _place("e33", 300, 300, {"R": 270, "M": 1}),
			"up": _place("e33", 900, 300)
		}
	)
	var state := State.create(world)
	var type: Script = Registry.lookup("e33")
	var left := _by_id(state, "left")
	check(left.heading == 180000, "R 270 flies left")
	check(_by_id(state, "right").heading == 0, "R 90 flies right")
	check(_by_id(state, "up").heading == 270000, "A missing R flies up")
	check(
		type.bounds(left) == [-28 * S, -12 * S, 24 * S, 12 * S],
		"A level flyer's body lies along its travel"
	)
	_activate(left)
	var start_x: int = left.x
	type.step(left, state, world)
	check(left.vx == -312 * 60 / 60, "It eases up from rest")
	for _tick in 59:
		type.step(left, state, world)
	check(left.vx == -312 * 60 and left.y == 200 * S, "After a second it glides at 312 px/s")
	check(left.x < start_x, "It ignores terrain and keeps flying")
	state.x = 100 * S
	state.y = 300 * S
	var seek := _by_id(state, "seek")
	seek.status = Registry.WAITING
	type.activate(seek, state, world)
	check(seek.heading == 180000, "A seeking flyer already heading at the player keeps going")
	state.x = 700 * S
	type.activate(seek, state, world)
	check(seek.heading == 0, "A seeking flyer turns round toward the player")
	var plain := _by_id(state, "right")
	_activate(plain)
	state.x = plain.x
	state.y = plain.y - 4 * S
	state.vy = 200 * 60
	type.contact(plain, state, world, 0)
	check(
		plain.status == Registry.DEFEATED and state.vy < 0, "Landing on it bounces and defeats it"
	)
	var up := _by_id(state, "up")
	_activate(up)
	state.x = up.x
	state.y = up.y + 30 * S
	state.invulnerable = 0
	type.contact(up, state, world, 0)
	check(state.invulnerable > 0, "Touching it from below hurts")
	check(_degrades("e33", {"M": 3}), "An unknown mirror becomes a placeholder")


func dice_checks() -> void:
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


func egg_block_checks() -> void:
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


func spore_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 1000, 316, {"E1": "2000"}),
			"spore": _place("e13", 500, 100),
			"sprout": _place("e12", 800, 284)
		}
	)
	var state := State.create(world)
	state.x = 1100 * S
	state.y = 300 * S - S / 16
	var spore := _by_id(state, "spore")
	var type: Script = Registry.lookup("e13")
	_activate(spore)
	for _tick in 48:
		Sim.advance(state, 0, world)
	check(spore.vx < 0 and spore.facing == 1, "The spore sways left, then turns after 0.8 s")
	check(spore.vy == 64 * 60, "The spore falls at no more than 64 px/s")
	check(type.sway_period(140) == 36 and type.sway_period(240) == 24, "The sway quickens")
	var landed := false
	for _tick in 400:
		Sim.advance(state, 0, world)
		if spore.status == Registry.DEFEATED:
			landed = true
			break
	check(landed, "The spore lands")
	var grown: Array = state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "e12" and entity.source_index == -1
	)
	check(grown.size() == 1 and grown[0].mode == 1, "A landed spore grows into a waking sprout")
	var sprout := _by_id(state, "sprout")
	var sprout_type: Script = Registry.lookup("e12")
	_activate(sprout)
	var hopped := false
	for _tick in 30:
		Sim.advance(state, 0, world)
		hopped = hopped or sprout.vy < 0
	check(hopped and sprout.x < 800 * S, "The sprout hops along its facing")
	state.x = sprout.x
	state.y = sprout.y - 10 * S
	state.vy = 200 * 60
	sprout.contact = 0
	sprout_type.contact(sprout, state, world, 0)
	check(sprout.status == Registry.DEFEATED and state.vy < 0, "Landing on a sprout defeats it")
	var hurt_world := _world_for({"spore": _place("e13", 500, 100)})
	var hurt := State.create(hurt_world)
	var touch := _by_id(hurt, "spore")
	_activate(touch)
	hurt.x = touch.x
	hurt.y = touch.y + 30 * S
	type.contact(touch, hurt, hurt_world, 0)
	check(hurt.invulnerable > 0, "Touching a spore hurts")


func _shots(state: Dictionary) -> Array:
	return state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "enemy_shot" and entity.status == 1
	)


func launcher_checks() -> void:
	var world := _world_for(
		{
			"fixed": _place("e37", 600, 200, {"E1": "Static"}),
			"aimed": _place("e37", 600, 600, {"E1": "Aim", "F": 1})
		}
	)
	var state := State.create(world)
	state.x = 300 * S
	state.y = 216 * S
	var type: Script = Registry.lookup("e37")
	var fixed := _by_id(state, "fixed")
	_activate(fixed)
	check(type.solid_box(fixed) == [584 * S, 184 * S, 616 * S, 216 * S], "The launcher is a solid")
	for _tick in 30:
		type.step(fixed, state, world)
	check(_shots(state).is_empty(), "The shot waits for its half-second cue")
	type.step(fixed, state, world)
	var shots := _shots(state)
	check(shots.size() == 1, "A fixed launcher fires one shot")
	if shots.size() == 1:
		check(shots[0].vx == -296 * 60 and shots[0].vy == 0, "It fires level toward the player")
	for _tick in 400:
		type.step(fixed, state, world)
	check(_shots(state).size() == 1, "It does not fire again while its shot remains")
	shots[0].status = Registry.DEFEATED
	type.step(fixed, state, world)
	for _tick in 31:
		type.step(fixed, state, world)
	check(_shots(state).size() == 1, "Once the shot is gone it fires again")
	var aimed := _by_id(state, "aimed")
	_activate(aimed)
	state.x = 900 * S
	state.y = 632 * S
	for _tick in 31:
		type.step(aimed, state, world)
	var aimed_shot: Dictionary = _shots(state).back()
	check(aimed_shot.vx > 0 and aimed_shot.form == 1, "An aiming launcher fires at the player")
	check(_degrades("e37", {"E1": "Spin"}), "An unknown launcher mode becomes a placeholder")
	check(_degrades("e37", {"E1": "Static", "F": 2}), "The homing shot form degrades")


func shot_checks() -> void:
	var world := _world_for({"wall": _place("o28", 300, 200)})
	var state := State.create(world)
	state.x = 900 * S
	state.y = 600 * S
	var shot := Registry.spawn_dynamic(
		state, world, "enemy_shot", 500 * S, 200 * S, {"vx": -296 * 60, "form": 1, "facing": -1}
	)
	var paused := false
	for _tick in 60:
		Sim.advance(state, 0, world)
		paused = paused or shot.pause > 0
	check(paused, "A bouncing shot pauses against a solid")
	check(shot.vx > 0 and shot.x > 332 * S + 17 * S - S, "Then it reflects off the solid")
	var plain := Registry.spawn_dynamic(
		state, world, "enemy_shot", 500 * S, 400 * S, {"vx": -296 * 60, "facing": -1}
	)
	var type: Script = Registry.lookup("enemy_shot")
	type.step(plain, state, world)
	check(plain.x == 500 * S - 296 * 60, "A straight shot flies at 296 px/s")
	state.x = plain.x
	state.y = plain.y - 4 * S
	state.vy = 100 * 60
	type.contact(plain, state, world, 0)
	check(plain.falling == 1 and state.vy < 0, "Landing on a shot stops it and it drops")
	type.step(plain, state, world)
	check(plain.vy == 1024 and plain.x == 500 * S - 296 * 60, "A stopped shot falls")
	state = State.create(world)
	var side := Registry.spawn_dynamic(
		state, world, "enemy_shot", 700 * S, 400 * S, {"vx": -296 * 60, "facing": -1}
	)
	state.x = side.x
	state.y = side.y + 30 * S
	state.invulnerable = 0
	type.contact(side, state, world, 0)
	check(state.invulnerable > 0, "A shot hurts from the side")


func melon_checks() -> void:
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


func leaper_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 1000, 316, {"E1": "2000"}),
			"plain": _place("e17", 500, 284),
			"coins": _place("e17", 1200, 284, {"F": 1})
		}
	)
	var state := State.create(world)
	state.x = 850 * S
	state.y = 300 * S - S / 16
	var type: Script = Registry.lookup("e17")
	var plain := _by_id(state, "plain")
	_activate(plain)
	for _tick in 50:
		Sim.advance(state, 0, world)
	check(plain.phase == type.WAIT and plain.vx == 0, "The leaper waits on the ground")
	var left: bool = false
	for _tick in 40:
		Sim.advance(state, 0, world)
		left = left or plain.vy < 0
	check(left and plain.x < 500 * S, "After a second and a crouch it leaps forward")
	check(
		type.solid_box(plain)[3] - type.solid_box(plain)[1] == 2 * S,
		"Its deck is top-only and thin"
	)
	var coins := _by_id(state, "coins")
	_activate(coins)
	var deck: Array = type.solid_box(coins)
	state.x = coins.x
	state.y = deck[1]
	state.on_floor = 1
	type.contact(coins, state, world, 0)
	check(coins.squashed == 1 and coins.status == Registry.ACTIVE, "Standing on the deck holds it")
	state.move_action = Moves.POUND_LAND
	type.contact(coins, state, world, 0)
	check(coins.status == Registry.DEFEATED, "A ground pound on its deck defeats it")
	var dropped: Array = state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "o1" and entity.source_index == -1
	)
	check(dropped.size() == 3, "F 1 releases three coins")
	state.move_action = 0
	state.x = plain.x + 10 * S
	state.y = plain.y + 30 * S
	state.invulnerable = 0
	plain.status = Registry.ACTIVE
	type.contact(plain, state, world, 0)
	check(state.invulnerable > 0, "Touching it from the side hurts")
	var egg := {"code": "o7", "x": plain.x, "fall_on_terrain": 0}
	check(type.projectile_contact(plain, egg, state, world) == 1, "A thrown egg is spent on it")
	check(plain.status == Registry.DEFEATED, "A thrown egg defeats it")
	check(_degrades("e17", {"F": 3}), "An unknown leaper colour becomes a placeholder")


func bumper_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 1000, 316, {"E1": "2000"}),
			"walker": _place("e19", 500, 284),
			"slider": _place("e19", 900, 284, {"F": 1}),
			"flyer": _place("e19", 1300, 150, {"F": 2})
		}
	)
	var state := State.create(world)
	state.x = 700 * S
	state.y = 300 * S - S / 16
	var type: Script = Registry.lookup("e19")
	var walker := _by_id(state, "walker")
	var slider := _by_id(state, "slider")
	var flyer := _by_id(state, "flyer")
	for entity: Dictionary in [walker, slider, flyer]:
		_activate(entity)
	var stepped := false
	var slid := false
	for _tick in 240:
		Sim.advance(state, 0, world)
		stepped = stepped or walker.phase == type.STEP
		slid = slid or slider.phase == type.SLIDE
	check(stepped, "The plain bumper idles, then waddles")
	check(slid, "The sliding bumper hops and belly-slides")
	check(slider.x < 900 * S, "It slides toward the player")
	check(flyer.phase == type.FLY and flyer.y < 200 * S, "The flying bumper stays aloft")
	check(type.sweep_speed(0, 150, -144, 144) == -144, "A sweep starts at its first speed")
	check(type.sweep_speed(150, 150, -144, 144) == 144, "A sweep reaches the other speed")
	state = State.create(world)
	walker = _by_id(state, "walker")
	_activate(walker)
	state.x = walker.x - 20 * S
	state.y = walker.y + 16 * S
	state.on_floor = 1
	state.invulnerable = 0
	type.contact(walker, state, world, 0)
	check(state.vx == -224 * 60 and state.invulnerable == 0, "Touching it shoves without hurting")
	state.x = walker.x
	state.y = walker.y - 6 * S
	state.on_floor = 0
	state.vy = 200 * 60
	type.contact(walker, state, world, 0)
	check(state.vy < 0, "Landing on it bounces the player")
	var egg := {"code": "o7", "x": walker.x, "fall_on_terrain": 0}
	check(type.projectile_contact(walker, egg, state, world) == 3, "An egg passes on")
	check(walker.status == Registry.DEFEATED, "An egg defeats it")
	check(_degrades("e19", {"F": 3}), "An unknown bumper form becomes a placeholder")


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
