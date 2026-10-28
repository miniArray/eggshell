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
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	registration_checks()
	thorn_checks()
	colour_block_checks()
	grow_block_checks()
	bridge_checks()
	runner_checks()
	snapshot_checks()
	print("S7_OBJECTS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func level(objects: Dictionary) -> Dictionary:
	return {
		"version": "s3.8.0",
		"name": "Invented objects",
		"author": "Eggshell",
		"desc": "",
		"startpoint": {"map": 1, "X": 64, "Y": 100},
		"maps": {"map1": {"width": 4096, "height": 1024, "objects": objects}}
	}


func build(objects: Dictionary) -> Dictionary:
	return World.build(JSON.stringify(level(objects)), {"tilemaps": {}})


func world_for(objects: Dictionary) -> Dictionary:
	var built := build(objects)
	check(built.ok, "Invented placements compile: " + str(built.get("error", "")))
	return built.get("world", {})


func by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	check(false, "Expected placement exists: " + id)
	return {}


func place(code: String, x: int, y: int, options: Dictionary = {}) -> Dictionary:
	var result := {"A": code, "X": x, "Y": y}
	result.merge(options, true)
	return result


func stand_on(state: Dictionary, top: int, x: int) -> void:
	state.x = x
	state.y = top - S / 16
	state.vx = 0
	state.vy = 0
	state.on_floor = 1


func registration_checks() -> void:
	for code: String in ["o12", "o29", "o10", "p2", "e7", "e9"]:
		check(Registry.implemented(code), "Slice 7 code is registered: " + code)
	var codes := Registry.codes()
	var seen := {}
	for code: String in codes:
		check(not seen.has(code), "Code appears once: " + code)
		seen[code] = true
	for pair: Array in [["o12", {"F": 2}], ["o29", {"F": 3}]]:
		var built := build({"one": place(pair[0], 200, 200, pair[1])})
		check(not built.ok, "Out-of-range form is not silently accepted: " + pair[0])
	for pair: Array in [["o12", {"F": 0.5}], ["o29", {"F": "x"}], ["p2", {"E1": "wide"}]]:
		var built := build({"one": place(pair[0], 200, 200, pair[1])})
		check(not built.ok, "Malformed option is rejected: " + pair[0])


func thorn_checks() -> void:
	var world := world_for({"thorn": place("o12", 200, 200, {"F": 1})})
	var state := State.create(world)
	var thorn := by_id(state, "thorn")
	check(thorn.form == 1, "Thorn keeps its second form")
	stand_on(state, 184 * S, 200 * S)
	Sim.advance(state, 0, world)
	check(state.life_phase == Life.DEAD, "Touching a thorn from above is fatal")
	state = State.create(world)
	state.x = 200 * S
	state.y = 330 * S
	state.vy = 0
	Sim.advance(state, 0, world)
	check(state.life_phase == Life.PLAY, "A thorn far below the player is harmless")
	thorn = by_id(state, "thorn")
	var egg := Registry.spawn_dynamic(
		state, world, "o7", 170 * S, 200 * S, {"mode": 1, "vx": 16 * S, "vy": 0, "bounces": 4}
	)
	egg.status = Registry.ACTIVE
	Collision.begin_step(state, world, Registry)
	Registry.lookup("o7").travel(egg, state, world)
	check(thorn.status == Registry.DEFEATED, "A thrown egg breaks a thorn")
	Collision.begin_step(state, world, Registry)
	check(Registry.lookup("o12").solid_box(thorn).is_empty(), "A broken thorn is no longer solid")


func colour_block_checks() -> void:
	var world := world_for({"block": place("o29", 300, 200, {"F": 1})})
	var state := State.create(world)
	var block := by_id(state, "block")
	var type: Script = Registry.lookup("o29")
	check(type.solid_box(block) == [268 * S, 184 * S, 332 * S, 216 * S], "Colour block is 64x32")
	var egg := {"code": "o7", "x": 300 * S, "bounces": 3}
	check(type.projectile_contact(block, egg, state, world) == 3, "Egg reacts and continues")
	check(block.form == 2 and egg.bounces == 4, "Egg hit advances the colour and refunds a hit")
	type.projectile_contact(block, egg, state, world)
	check(block.status == Registry.DEFEATED, "Last colour breaks on the next egg hit")
	block.status = Registry.ACTIVE
	block.form = 0
	type.hit(block, state, world, Hits.POUND, 0)
	check(block.form == 0, "Only eggs change the colour")
	var flying := Registry.spawn_dynamic(
		state, world, "o7", 240 * S, 200 * S, {"mode": 1, "vx": 16 * S, "vy": 0, "bounces": 4}
	)
	flying.status = Registry.ACTIVE
	Collision.begin_step(state, world, Registry)
	Registry.lookup("o7").travel(flying, state, world)
	check(block.form == 1, "A travelling egg that reaches the block edge hits it")
	check(flying.vx < 0 and flying.bounces == 4, "The egg still bounces; the block refunds the hit")
	var rock_world := world_for({"rock": place("o28", 300, 200)})
	var rock_state := State.create(rock_world)
	var rock := by_id(rock_state, "rock")
	var thrown := Registry.spawn_dynamic(
		rock_state, rock_world, "o7", 250 * S, 200 * S, {"mode": 1, "vx": 16 * S, "bounces": 4}
	)
	thrown.status = Registry.ACTIVE
	Collision.begin_step(rock_state, rock_world, Registry)
	Registry.lookup("o7").travel(thrown, rock_state, rock_world)
	check(rock.form == 1, "Edge contact also reaches other full solids that react to eggs")


func grow_block_checks() -> void:
	var world := world_for({"grow": place("o10", 400, 200)})
	var state := State.create(world)
	var block := by_id(state, "grow")
	var type: Script = Registry.lookup("o10")
	check(type.solid_box(block) == [384 * S, 184 * S, 416 * S, 216 * S], "Small block is 32x32")
	state.x = 400 * S
	state.y = 275 * S
	type.contact(block, state, world, 0)
	check(block.phase == type.IDLE, "A player more than 2 px below does not trigger growth")
	state.y = 273 * S
	type.contact(block, state, world, 0)
	check(block.phase == type.RISE, "Head contact within 2 px starts growth")
	for tick in 12:
		type.step(block, state, world)
	check(
		type.solid_box(block) == [368 * S, 90 * S, 432 * S, 154 * S],
		"After 0.2 s the block is 64 px and 62 px higher"
	)
	for tick in 12:
		type.step(block, state, world)
	check(
		type.solid_box(block) == [368 * S, 120 * S, 432 * S, 184 * S],
		"It settles with its bottom 32 px above the start"
	)
	type.contact(block, state, world, 0)
	check(block.phase == type.HOLD, "A grown block does not restart")
	for tick in 336:
		type.step(block, state, world)
	check(block.phase == type.SHRINK, "Shrinking starts six seconds after the hit")
	for tick in 12:
		type.step(block, state, world)
	check(
		block.phase == type.IDLE and type.solid_box(block) == [384 * S, 184 * S, 416 * S, 216 * S],
		"Block returns to its original size and place"
	)
	check(type.valid(block), "Saved growth fields stay valid")


func bridge_checks() -> void:
	var world := world_for(
		{"bridge": place("p2", 600, 300, {"E1": "160"}), "plain": place("p2", 900, 300)}
	)
	var state := State.create(world)
	var bridge := by_id(state, "bridge")
	var type: Script = Registry.lookup("p2")
	check(type.SOLID == 2, "Bridge is top-only")
	check(
		type.solid_box(bridge) == [520 * S, 284 * S, 680 * S, 286 * S],
		"Bridge strip uses E1 width at the body's top edge"
	)
	check(by_id(state, "plain").width == 96 * S, "Missing width keeps the 96 px default")
	state.x = 600 * S
	state.y = 270 * S
	state.vy = 0
	for tick in 30:
		Sim.advance(state, 0, world)
	check(state.y <= 284 * S and state.y > 283 * S, "Falling player lands on the bridge top")
	state.x = 600 * S
	state.y = 320 * S
	state.vy = -600 * 60
	Collision.begin_step(state, world, Registry)
	check(
		Collision.vertical(state, world, Sim.PLAYER_BOX, -40 * S) == -40 * S,
		"Rising player passes through the bridge"
	)


func runner_checks() -> void:
	var world := world_for(
		{"plain": place("e7", 200, 200), "careful": place("e9", 400, 200, {"M": 1})}
	)
	var state := State.create(world)
	var plain := by_id(state, "plain")
	var careful := by_id(state, "careful")
	var walker: Script = Registry.lookup("e6")
	check(plain.mode == walker.BARE and plain.inside == 0, "Placed runner walks without a shell")
	check(plain.colour == 0 and careful.colour == 1, "The second code selects the careful colour")
	check(careful.facing == 1, "Mirror option turns the runner right")
	check(Registry.is_enemy("e7") and Registry.is_enemy("e9"), "Runners join the enemy view")
	check(
		Registry.lookup("e9").view_state(careful, state).animation == "1Walk",
		"Runner draws the colour walk animation"
	)
	plain.status = Registry.ACTIVE
	Registry.lookup("e7").hit(plain, state, world, Hits.EGG, 0)
	check(plain.status == Registry.DEFEATED, "An egg defeats a placed runner")


func snapshot_checks() -> void:
	var world := world_for(
		{
			"a": place("o12", 100, 100),
			"b": place("o29", 200, 100, {"F": 2}),
			"c": place("o10", 300, 100),
			"d": place("p2", 400, 100, {"E1": "64.00000000000728"}),
			"e": place("e7", 500, 100),
			"f": place("e9", 600, 100, {"M": 2})
		}
	)
	var state := State.create(world)
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok and Snapshot.encode(decoded.state) == bytes, "Slice 7 objects round trip")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
