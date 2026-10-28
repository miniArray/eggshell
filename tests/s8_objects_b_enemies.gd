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
	_soft_walker_checks()
	_soft_giant_checks()
	_gust_checks()
	_spore_checks()
	_launcher_checks()
	_shot_checks()
	_leaper_checks()
	_bumper_checks()
	_stilt_checks()
	_helmet_checks()
	_slime_checks()
	_ghost_checks()
	print("S8_OBJECTS_B_ENEMIES_RESULT: %d assertions, %d failures" % [checks, failures])
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


func _ledge_world(extra: Dictionary) -> Dictionary:
	var objects := {"floor": _place("p2", 500, 316, {"E1": "320"})}
	objects.merge(extra, true)
	return _world_for(objects)


func _activate(entity: Dictionary) -> void:
	entity.status = Registry.ACTIVE
	entity.started = 1


func _soft_walker_checks() -> void:
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


func _soft_giant_checks() -> void:
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


func _gust_checks() -> void:
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
	var tilted := _world_for({"tilt": _place("e33", 300, 300, {"R": 240.0220428328622})})
	check(
		_by_id(State.create(tilted), "tilt").heading == 150022,
		"A fractional placement angle loads and keeps its millidegrees"
	)


func _spore_checks() -> void:
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


func _launcher_checks() -> void:
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


func _shot_checks() -> void:
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


func _leaper_checks() -> void:
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


func _bumper_checks() -> void:
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


func _stilt_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 700, 316, {"E1": "400"}),
			"tall": _place("e35", 600, 284, {"E1": "82", "F": 2})
		}
	)
	var state := State.create(world)
	state.x = 890 * S
	state.y = 300 * S - S / 16
	var type: Script = Registry.lookup("e35")
	var tall := _by_id(state, "tall")
	check(
		tall.y == 300 * S and tall.height == 100 * S,
		"The stilts stand on the floor, E1 + 18 px tall"
	)
	_activate(tall)
	var start: int = tall.x
	for _tick in 36:
		Sim.advance(state, 0, world)
	check(tall.x == start - 24 * S, "It strides 24 px every 0.6 s")
	var turned := false
	for _tick in 36 * 6:
		Sim.advance(state, 0, world)
		turned = turned or tall.facing == 1
	check(turned and tall.x >= 500 * S, "It turns at the ledge")
	state = State.create(world)
	tall = _by_id(state, "tall")
	_activate(tall)
	state.x = tall.x
	state.y = tall.y - 40 * S
	state.invulnerable = 0
	type.contact(tall, state, world, 0)
	check(state.invulnerable > 0, "Its legs hurt")
	tall.contact = 0
	state.y = type.top(tall) + 10 * S
	state.vy = 200 * 60
	type.contact(tall, state, world, 0)
	check(tall.status == Registry.DEFEATED and state.vy < 0, "Landing on top unseats the rider")
	var riders: Array = state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == "e1" and entity.source_index == -1
	)
	check(riders.size() == 1 and riders[0].variant == 2, "The rider walks on in its colour")
	state = State.create(world)
	tall = _by_id(state, "tall")
	_activate(tall)
	var low_egg := {"code": "o7", "x": tall.x - 30 * S, "y": tall.y - 10 * S, "fall_on_terrain": 0}
	check(
		type.projectile_contact(tall, low_egg, state, world) == 1, "An egg is spent on the stilts"
	)
	check(tall.phase == type.KNOCKED and tall.vx > 0, "A low egg knocks it back")
	var high_egg := {"code": "o7", "x": tall.x, "y": type.top(tall) + 5 * S, "fall_on_terrain": 0}
	type.projectile_contact(tall, high_egg, state, world)
	check(tall.status == Registry.DEFEATED, "An egg at the rider unseats it")
	check(_degrades("e35", {"F": 5}), "An unknown rider colour becomes a placeholder")


func _helmet_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 1000, 316, {"E1": "2000"}),
			"grunt": _place("e29", 500, 284),
			"runner": _place("e29", 900, 284, {"F": 1})
		}
	)
	var state := State.create(world)
	state.x = 1300 * S
	state.y = 300 * S - S / 16
	var type: Script = Registry.lookup("e29")
	var grunt := _by_id(state, "grunt")
	var runner := _by_id(state, "runner")
	_activate(grunt)
	_activate(runner)
	Sim.advance(state, 0, world)
	check(grunt.vx == -48 * 60 and runner.vx == -144 * 60, "F 1 runs at 144 px/s, F 0 walks at 48")
	state.x = grunt.x
	state.y = grunt.y - 20 * S
	state.invulnerable = 0
	type.contact(grunt, state, world, 0)
	check(
		state.invulnerable > 0 and grunt.status == Registry.ACTIVE,
		"Its helmet hurts even from above"
	)
	var egg := {"code": "o7", "x": grunt.x - 20 * S, "fall_on_terrain": 0}
	check(type.projectile_contact(grunt, egg, state, world) == 1, "An egg is spent on the helmet")
	check(grunt.helmet == 0 and grunt.vx > 0 and grunt.vy < 0, "The egg knocks the helmet off")
	state.x = 1300 * S
	state.y = 300 * S - S / 16
	state.invulnerable = 0
	var ran := false
	for _tick in 120:
		Sim.advance(state, 0, world)
		ran = ran or grunt.phase == type.RUN
	check(ran and grunt.speed == 144, "Without its helmet it lands, blushes and runs")
	grunt.contact = 0
	state.x = grunt.x
	state.y = grunt.y - 20 * S
	state.vy = 200 * 60
	type.contact(grunt, state, world, 0)
	check(grunt.status == Registry.DEFEATED and state.vy < 0, "A bare walker can be stomped")
	check(_degrades("e29", {"F": 2}), "An unknown helmet walker form becomes a placeholder")


func _slime_checks() -> void:
	var world := _world_for(
		{
			"floor": _place("p2", 1000, 316, {"E1": "2000"}),
			"ceiling": _place("o28", 600, 112),
			"slime": _place("e15", 400, 284),
			"drip": _place("e15", 600, 168, {"F": 1})
		}
	)
	var state := State.create(world)
	state.x = 900 * S
	state.y = 300 * S - S / 16
	var type: Script = Registry.lookup("e15")
	var slime := _by_id(state, "slime")
	var drip := _by_id(state, "drip")
	check(drip.y == 152 * S and drip.hidden == 1, "The dripping form starts hidden 16 px up")
	_activate(slime)
	_activate(drip)
	for _tick in 3:
		Sim.advance(state, 0, world)
	check(slime.vx == -48 * 60, "The slime creeps at 48 px/s")
	check(drip.phase == type.HANG, "A ceiling holds the dripping form")
	state.x = 650 * S
	var dropped := false
	var stared := false
	for _tick in 120:
		Sim.advance(state, 0, world)
		dropped = dropped or drip.phase == type.DROP
		stared = stared or drip.phase == type.STARE
	check(dropped and drip.hidden == 0, "It drops when the player comes near")
	check(stared, "After a long drop it lands and stares at the player")
	slime.contact = 0
	state.x = slime.x
	state.y = slime.y - 4 * S
	type.contact(slime, state, world, 0)
	check(
		slime.phase == type.SQUASH and state.y == slime.y,
		"Landing on it squashes it under the player"
	)
	for _tick in 15:
		type.step(slime, state, world)
	check(slime.status == Registry.DEFEATED, "The squashed slime bursts")
	check(_degrades("e15", {"F": 2}), "An unknown slime form becomes a placeholder")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)


func _ghost_checks() -> void:
	var world := _world_for(
		{"ghost": _place("e26", 600, 300), "pink": _place("e26", 200, 300, {"F": 3})}
	)
	var state := State.create(world)
	state.x = 400 * S
	state.y = 300 * S
	state.facing = -1
	var type: Script = Registry.lookup("e26")
	var ghost := _by_id(state, "ghost")
	var pink := _by_id(state, "pink")
	_activate(ghost)
	_activate(pink)
	type.step(ghost, state, world)
	check(
		ghost.x == 600 * S - 64 * 60 and ghost.facing == -1,
		"Unwatched, it drifts toward the player"
	)
	state.facing = 1
	for _tick in 13:
		type.step(ghost, state, world)
	check(ghost.phase == type.HIDE, "Watched, it hides after 0.2 s")
	var hidden_x: int = ghost.x
	type.step(ghost, state, world)
	check(ghost.x == hidden_x, "A hiding ghost stays put")
	type.step(pink, state, world)
	check(type.solid_box(pink).is_empty(), "A moving pink ghost is not solid")
	state.facing = 1
	for _tick in 14:
		type.step(pink, state, world)
	check(pink.phase == type.STALK, "The pink ghost behind the player keeps coming")
	state.facing = -1
	for _tick in 14:
		type.step(pink, state, world)
	check(not type.solid_box(pink).is_empty(), "A hiding pink ghost is a solid block")
	state.facing = -1
	for _tick in 14:
		type.step(ghost, state, world)
	check(ghost.phase == type.STALK, "Looked away from, it comes out again")
	var front := {"code": "o7", "x": ghost.x - 20 * S, "vx": 300 * 60, "fall_on_terrain": 0}
	var behind := {"code": "o7", "x": ghost.x + 20 * S, "vx": -300 * 60, "fall_on_terrain": 0}
	check(type.projectile_contact(ghost, behind, state, world) == 0, "An egg from behind passes")
	check(type.projectile_contact(ghost, front, state, world) == 3, "An egg at its face defeats it")
	check(ghost.status == Registry.DEFEATED, "It leaves a star when defeated")
	check(_degrades("e26", {"F": 4}), "An unknown ghost form becomes a placeholder")
