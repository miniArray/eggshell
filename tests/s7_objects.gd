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
	hopper_checks()
	producer_checks()
	spine_checks()
	flyer_checks()
	petal_checks()
	juggler_checks()
	egg_terrain_checks()
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


func ledge_world(extra: Dictionary) -> Dictionary:
	var objects := {
		"floor": place("p2", 500, 316, {"E1": "320"}),
		"rest": place("p2", 900, 316, {"E1": "200"})
	}
	objects.merge(extra, true)
	return world_for(objects)


func rest_player(state: Dictionary) -> void:
	state.x = 900 * S
	state.y = 300 * S - S / 16
	state.vx = 0
	state.vy = 0


func hopper_checks() -> void:
	var world := ledge_world({"spike": place("e40", 500, 200)})
	var state := State.create(world)
	rest_player(state)
	var spike := by_id(state, "spike")
	var landed := -1
	var hopped := false
	for tick in 240:
		Sim.advance(state, 0, world)
		if landed < 0 and spike.sink_window:
			landed = tick
		if landed >= 0 and spike.vy < -300 * 60 and not spike.sinking:
			hopped = true
		if spike.sinking:
			break
	check(landed > 0, "Spiked body falls and lands on support")
	check(hopped, "First landing starts a high hop on the next tick")
	check(spike.sinking == 1, "Landing again inside one second starts sinking")
	var before: int = spike.y
	for tick in 60:
		Sim.advance(state, 0, world)
	check(spike.y > 316 * S or spike.status != 1, "A sinking body falls through the support")
	check(state.life_phase == Life.PLAY and before < spike.y, "Player was never touched")
	var yellow_world := ledge_world({"spike": place("e40", 500, 200, {"F": 1})})
	state = State.create(yellow_world)
	rest_player(state)
	spike = by_id(state, "spike")
	for tick in 120:
		Sim.advance(state, 0, yellow_world)
	check(spike.status == Registry.DEFEATED, "The second form breaks on landing")
	check(not build({"one": place("e40", 1, 1, {"F": 2})}).ok, "Unknown form is refused")
	state = State.create(world)
	spike = by_id(state, "spike")
	spike.status = Registry.ACTIVE
	state.x = spike.x
	state.y = spike.y + 20 * S
	var type: Script = Registry.lookup("e40")
	type.contact(spike, state, world, 0)
	check(state.invulnerable > 0, "Touching the body hurts the player")
	var egg := {"code": "o7", "x": spike.x, "fall_on_terrain": 0}
	check(type.projectile_contact(spike, egg, state, world) == 3, "Egg reacts and continues")
	check(
		spike.status == Registry.DEFEATED and egg.fall_on_terrain == 1,
		"Egg defeats the body and falls at its next terrain contact"
	)


func producer_checks() -> void:
	var world := ledge_world({"plant": place("o17", 500, 284, {"E1": "e40"})})
	var state := State.create(world)
	rest_player(state)
	var released := {}
	for tick in 80:
		Sim.advance(state, 0, world)
		for entity: Dictionary in state.entities:
			if entity.code == "e40" and released.is_empty():
				released = entity.duplicate()
	var plant := by_id(state, "plant")
	check(plant.unavailable == 0, "Producer can release its spiked payload")
	check(not released.is_empty(), "Producer releases a spiked body")
	if released.is_empty():
		return
	check(released.source_index == -1 and released.can_respawn == 0, "Released body is runtime")
	check(
		released.vx >= -176 * 60 and released.vx <= 176 * 60, "Release speed is within 176 px/s"
	)
	check(released.colour == 0, "Released body uses the first form")


func spine_checks() -> void:
	var world := ledge_world(
		{"fast": place("e25", 450, 284), "slow": place("e25", 560, 284, {"F": 1, "M": 1})}
	)
	var state := State.create(world)
	rest_player(state)
	state.x = 2000 * S
	var fast := by_id(state, "fast")
	var slow := by_id(state, "slow")
	var type: Script = Registry.lookup("e25")
	for entity: Dictionary in [fast, slow]:
		entity.status = Registry.ACTIVE
		entity.started = 1
	var x0: int = fast.x
	var x1: int = slow.x
	Collision.begin_step(state, world, Registry)
	type.step(fast, state, world)
	type.step(slow, state, world)
	check(fast.x - x0 == -192 * 60, "First form walks left at 192 px/s")
	check(slow.x - x1 == 128 * 60, "Second form walks right at 128 px/s")
	state.x = fast.x + 90 * S
	state.y = fast.y
	Collision.begin_step(state, world, Registry)
	type.step(fast, state, world)
	check(fast.mode == type.SPIKE and fast.vx == 0, "A near player raises the spines")
	check(fast.facing == 1, "Raised spines face the player")
	for tick in 20:
		type.step(fast, state, world)
	check(fast.spine_w == 64 and fast.spine_h == 62, "Spines reach full size after 20 ticks")
	state.x = fast.x + 20 * S
	state.y = fast.y + 16 * S
	state.invulnerable = 0
	type.contact(fast, state, world, 0)
	check(state.invulnerable > 0, "Raised spines hurt the player")
	check(type.tongue(fast, state, world) == 0, "Raised spines cannot be eaten")
	var egg := {"code": "o7", "x": fast.x, "fall_on_terrain": 0}
	check(type.projectile_contact(fast, egg, state, world) == 1, "Spines consume an egg")
	check(fast.mode == type.SHRINK and fast.status == 1, "The struck spines fold; the body lives")
	check(type.projectile_contact(fast, egg, state, world) == 0, "Folding spines ignore eggs")
	for tick in 20:
		type.step(fast, state, world)
	check(fast.mode == type.WALK and fast.cooldown == 60, "After folding it walks with a pause")
	check(type.valid(fast), "Spine state stays valid")
	type.projectile_contact(fast, egg, state, world)
	check(fast.status == Registry.DEFEATED and egg.fall_on_terrain == 1, "Egg defeats a walker")
	fast.status = Registry.ACTIVE
	fast.mode = type.SPIKE
	fast.timer = 59
	type.step(fast, state, world)
	check(fast.mode == type.SHRINK, "Spines fold one second after rising")


func flyer_checks() -> void:
	var world := world_for(
		{
			"calm": place("e30", 400, 200),
			"low": place("e30", 600, 200, {"F": 1, "E1": "1", "M": 1})
		}
	)
	var state := State.create(world)
	state.x = 3000 * S
	state.y = 900 * S
	var calm := by_id(state, "calm")
	var low := by_id(state, "low")
	var type: Script = Registry.lookup("e30")
	check(calm.drifts == 1 and low.drifts == 0, "E1 1 keeps the flyer in place horizontally")
	for entity: Dictionary in [calm, low]:
		entity.status = Registry.ACTIVE
		entity.started = 1
	for tick in 45:
		type.step(calm, state, world)
		type.step(low, state, world)
	check(calm.x == 400 * S - 45 * 64 * 60, "The flyer drifts left at 64 px/s")
	check(low.x == 600 * S, "A fixed flyer does not drift")
	check(calm.y == 136 * S and low.y == 264 * S, "Bobbing peaks 64 px from home after 0.75 s")
	for tick in 135:
		type.step(calm, state, world)
	check(calm.y == 200 * S and calm.bob == 0, "The bob repeats every three seconds")
	state.x = calm.x
	state.y = calm.y - 10 * S
	state.vy = 4 * S
	type.contact(calm, state, world, 0)
	check(calm.mode == type.STOMPED and state.vy < 0, "A stomp bounces the player and knocks the flyer")
	for tick in 6:
		type.step(calm, state, world)
	check(calm.y == 212 * S, "A stomp knocks the flyer 12 px down in 0.1 s")
	for tick in 7:
		type.step(calm, state, world)
	check(calm.mode == type.ANGRY, "After the stomp pose it turns angry")
	state.x = calm.x + 300 * S
	state.y = calm.y + 32 * S
	for tick in 60:
		type.step(calm, state, world)
	check(calm.mode == type.CHARGE and calm.facing == 1, "After one second it charges at the player")
	check(calm.vx == 256 * 60 and calm.vy == 0, "The charge aims 32 px above the feet at 256 px/s")
	var egg := {"code": "o7", "x": low.x - 30 * S, "vx": 16 * S, "vy": 0, "fall_on_terrain": 0}
	check(type.projectile_contact(low, egg, state, world) == 1, "An egg is absorbed")
	check(low.mode == type.STOMPED and low.knock_dx == 48 * S, "An egg knocks the flyer along its path")
	state.x = low.x
	state.y = low.y + 40 * S
	state.invulnerable = 0
	low.contact = 0
	type.contact(low, state, world, 0)
	check(state.invulnerable > 0, "Touching it from below hurts")
	check(type.valid(calm) and type.valid(low), "Flyer state stays valid")


func petals_of(state: Dictionary, stem: Dictionary) -> Array:
	var result := []
	for entity: Dictionary in state.entities:
		if entity.code == "enemy_petal" and entity.stem_token == stem.token and entity.status == 1:
			result.append(entity)
	return result


func petal_checks() -> void:
	var world := ledge_world({"stem": place("e18", 500, 284)})
	var state := State.create(world)
	rest_player(state)
	var stem := by_id(state, "stem")
	var type: Script = Registry.lookup("e18")
	var ticks := 0
	while stem.status != 1 and ticks < 5:
		Sim.advance(state, 0, world)
		ticks += 1
	check(stem.status == 1, "Stem activates near the player")
	while stem.timer < type.PETAL_TICK and ticks < 60:
		Sim.advance(state, 0, world)
		ticks += 1
	var petals := petals_of(state, stem)
	check(petals.size() == 5, "Face grows five petals after 0.3 s")
	for tick in 18:
		Sim.advance(state, 0, world)
	petals = petals_of(state, stem)
	var center: Array = type.face_center(stem)
	check(center[1] == stem.y - 32 * S, "Face rests 32 px above the stem centre")
	if petals.size() == 5:
		var top: Dictionary = petals[0]
		check(
			absi(top.x - center[0]) <= S and absi(top.y - (center[1] - 32 * S)) <= S,
			"First petal orbits 32 px above the face"
		)
		check(Registry.lookup("enemy_petal").valid(top), "Petal state is valid")
	while stem.phase == type.GROW and ticks < 600:
		Sim.advance(state, 0, world)
		ticks += 1
	check(stem.phase == type.SHOOT, "After dancing the stem prepares to shoot")
	check(stem.shoot_at >= 300 and stem.shoot_at <= 318, "Shot comes 3.7 to 4 s after the dance")
	for tick in 27:
		Sim.advance(state, 0, world)
	var flying := 0
	for entity: Dictionary in state.entities:
		if entity.code == "enemy_petal" and entity.mode == 1:
			flying += 1
			var speed: int = entity.vx * entity.vx + entity.vy * entity.vy
			check(absi(speed - 15360 * 15360) < 15360 * 400, "Petals fly at 256 px/s")
	check(flying == 5 and stem.phase == type.REGAIN, "All petals fly out and the face is gone")
	state = State.create(world)
	rest_player(state)
	stem = by_id(state, "stem")
	for tick in 40:
		Sim.advance(state, 0, world)
	check(petals_of(state, stem).size() == 5, "New stem has petals")
	state.move_impact += 1
	Sim.advance(state, 0, world)
	var dropped := 0
	for entity: Dictionary in state.entities:
		if entity.code == "enemy_petal" and entity.mode == 2:
			dropped += 1
	check(dropped == 5 and stem.phase == type.FADE, "A ground pound drops every attached petal")
	check(type.tongue(stem, state, world) == 0, "The stem cannot be eaten")
	var petal_type: Script = Registry.lookup("enemy_petal")
	var loose := petals_of(state, stem)[0] as Dictionary
	check(petal_type.tongue(loose, state, world) == 0, "A dropped petal cannot be eaten")
	for tick in 78:
		Sim.advance(state, 0, world)
	check(stem.phase == type.REGAIN, "The face fades 1.3 s after the pound")
	for tick in 180:
		Sim.advance(state, 0, world)
	check(stem.phase == type.GROW, "Petals regrow three seconds later")


func juggler_checks() -> void:
	var world := ledge_world({"head": place("e42", 500, 284)})
	var state := State.create(world)
	rest_player(state)
	var head := by_id(state, "head")
	var type: Script = Registry.lookup("e42")
	var ticks := 0
	while head.needle_token == 0 and ticks < 5:
		Sim.advance(state, 0, world)
		ticks += 1
	var needle: Dictionary = Registry.find_token(state, head.needle_token)
	check(not needle.is_empty() and needle.code == "e40", "The head starts holding a spiked hopper")
	if needle.is_empty():
		return
	check(needle.carrier == head.token, "The hopper is carried")
	check(needle.y == head.y - 58 * S, "A carried hopper sits 10 px above the head top")
	var tosses := 0
	var catches := 0
	var highest: int = needle.y
	var was_carried := true
	for tick in 600:
		Sim.advance(state, 0, world)
		highest = mini(highest, needle.y)
		var carried: bool = needle.carrier == head.token
		if was_carried and not carried:
			tosses += 1
		if carried and not was_carried:
			catches += 1
		was_carried = carried
	check(tosses >= 3 and catches >= 3, "The head keeps tossing and catching the hopper")
	check(
		highest < head.y - 58 * S - 150 * S and highest > head.y - 58 * S - 200 * S,
		"Every third toss rises about 176 px"
	)
	check(needle.status == 1 and state.life_phase == Life.PLAY, "The juggled hopper survives")
	check(type.valid(head), "Juggler state stays valid")
	check(type.tongue(head, state, world) == 0, "The head cannot be eaten")
	var egg := {"code": "o7", "x": head.x}
	check(type.projectile_contact(head, egg, state, world) == 0, "Eggs pass the head")
	state = State.create(world)
	rest_player(state)
	head = by_id(state, "head")
	for tick in 3:
		Sim.advance(state, 0, world)
	needle = Registry.find_token(state, head.needle_token)
	defeat(needle)
	var frowned := -1
	var regrown := -1
	for tick in 700:
		Sim.advance(state, 0, world)
		if frowned < 0 and head.frowning:
			frowned = tick
		if frowned >= 0 and regrown < 0 and head.needle_token and not head.frowning:
			regrown = tick
	check(frowned > 0, "Losing the hopper makes the head frown")
	check(regrown - frowned >= 380 and regrown - frowned <= 386, "A new hopper rises 6.4 s later")
	state.x = head.x
	state.y = head.y
	state.invulnerable = 0
	head.frowning = 0
	type.contact(head, state, world, 0)
	check(state.invulnerable > 0, "Touching the head hurts")


func defeat(entity: Dictionary) -> void:
	entity.status = Registry.DEFEATED


func tile_layer(name: String, cells: Array, columns: int, points: Array, water: bool) -> Dictionary:
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
		"solid": not water,
		"water": water
	}


func thrown_egg(state: Dictionary, world: Dictionary, x: int, y: int, vx: int, vy: int) -> Dictionary:
	var egg := Registry.spawn_dynamic(
		state, world, "o7", x, y, {"mode": 1, "vx": vx, "vy": vy, "bounces": 4}
	)
	egg.status = Registry.ACTIVE
	return egg


func egg_terrain_checks() -> void:
	var type: Script = Registry.lookup("o7")
	var world := world_for({})
	# One rising slope cell at column 4, row 4 (x 128..160, y 128..160).
	var cells := []
	for index in 64:
		cells.append(-1)
	cells[4 * 8 + 4] = 0
	world.layers = [tile_layer("slope", cells, 8, [0, 32, 32, 0, 32, 32], false)]
	var state := State.create(world)
	state.x = 2000 * S
	var egg := thrown_egg(state, world, 100 * S, 140 * S, 1024 * 60, 0)
	for tick in 2:
		Collision.begin_step(state, world, Registry)
		type.travel(egg, state, world)
	check(egg.bounces == 3 and egg.colour == 1, "A slope ricochet spends one hit")
	check(egg.vy < -900 * 60 and absi(egg.vx) < 200 * 60, "A 45 degree slope turns a level egg upward")
	var speed: int = egg.vx * egg.vx + egg.vy * egg.vy
	check(absi(speed - 61440 * 61440) < 61440 * 1200, "A ricochet keeps the egg speed")
	var wall_world := world_for({})
	var wall := []
	for index in 64:
		wall.append(0 if index % 8 == 4 else -1)
	wall_world.layers = [tile_layer("wall", wall, 8, [0, 0, 32, 0, 32, 32, 0, 32], false)]
	state = State.create(wall_world)
	state.x = 2000 * S
	egg = thrown_egg(state, wall_world, 100 * S, 100 * S, 1024 * 60, 0)
	for tick in 2:
		Collision.begin_step(state, wall_world, Registry)
		type.travel(egg, state, wall_world)
	check(egg.vx == -1024 * 60 and egg.vy == 0, "A flat wall reverses a level egg exactly")
	var pool := world_for({})
	var water := []
	for index in 64:
		water.append(0 if index >= 32 else -1)
	pool.layers = [tile_layer("pool", water, 8, [0, 0, 32, 0, 32, 32, 0, 32], true)]
	state = State.create(pool)
	state.x = 2000 * S
	egg = thrown_egg(state, pool, 40 * S, 120 * S, 1000 * 60, 200 * 60)
	for tick in 3:
		Collision.begin_step(state, pool, Registry)
		type.step(egg, state, pool)
	check(egg.mode == type.SKIP, "A shallow water entry skips")
	check(egg.skip_vx > 450 * 60 and egg.skip_vx < 520 * 60, "The skip starts at half speed")
	check(egg.skip_total > 120 and egg.skip_total < 150, "The skip lasts two seconds plus angle/24")
	var total: int = egg.skip_total
	var rose := false
	for tick in total:
		Collision.begin_step(state, pool, Registry)
		type.step(egg, state, pool)
		rose = rose or egg.vy == -256 * 60
	check(rose, "A skipping egg is pushed up while it touches water")
	check(egg.mode == type.STATIONARY and egg.vx == 0, "The skip ends as a resting egg")
	check(type.valid(egg), "Skip fields stay valid")
	state = State.create(pool)
	state.x = 2000 * S
	egg = thrown_egg(state, pool, 100 * S, 100 * S, 200 * 60, 1000 * 60)
	for tick in 3:
		Collision.begin_step(state, pool, Registry)
		type.step(egg, state, pool)
	check(
		egg.mode == type.STATIONARY and egg.despawn_ticks > 470,
		"A steep water entry sinks and starts the 8 s removal"
	)


func snapshot_checks() -> void:
	var world := world_for(
		{
			"a": place("o12", 100, 100),
			"b": place("o29", 200, 100, {"F": 2}),
			"c": place("o10", 300, 100),
			"d": place("p2", 400, 100, {"E1": "64.00000000000728"}),
			"e": place("e7", 500, 100),
			"f": place("e9", 600, 100, {"M": 2}),
			"g": place("e40", 700, 100, {"F": 1}),
			"h": place("o17", 800, 100, {"E1": "e40"}),
			"i": place("e25", 900, 100, {"F": 1, "M": 2}),
			"j": place("e30", 1000, 100, {"F": 1, "E1": "1", "M": 2}),
			"k": place("e18", 1100, 100),
			"l": place("e42", 1200, 100)
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
