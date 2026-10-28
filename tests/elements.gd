extends SceneTree
## Fire and ice on invented placements and controlled states. No frames,
## recordings or devices.
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Hits = preload("res://src/sim/hits.gd")
const Moves = preload("res://src/sim/moves.gd")
const Elements = preload("res://src/sim/elements.gd")
const Reactions = preload("res://src/sim/element_reactions.gd")
const Shot = preload("res://src/sim/types/element_shot.gd")
const S := State.SCALE
## Options that make each reacting code compile in its ordinary form.
const TYPE_OPTIONS := {
	"e14": {"F": 1},
	"e22": {"E1": "90"},
	"e33": {"R": 270},
	"e35": {"E1": "82"},
	"e43": {"E1": "2", "E2": "0.5", "E3": "192"},
}
var checks := 0
var failures := 0


func _initialize() -> void:
	var collision: Script = Collision
	if "verify_index" in collision:
		collision.set("verify_index", true)
	_leaf_checks()
	_melon_checks()
	_shot_checks()
	_freeze_checks()
	_thaw_checks()
	_immune_checks()
	_bubble_checks()
	_lamp_checks()
	_cloud_checks()
	_launcher_checks()
	_snapshot_checks()
	_every_type_checks()
	if "verify_failures" in collision:
		check(int(collision.get("verify_failures")) == 0, "Indexed solid queries match a full scan")
	print("ELEMENTS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _level(objects: Dictionary) -> Dictionary:
	return {
		"version": "s3.8.0",
		"name": "Invented elements",
		"author": "Eggshell",
		"desc": "",
		"startpoint": {"map": 1, "X": 64, "Y": 100},
		"maps": {"map1": {"width": 4096, "height": 1024, "objects": objects}}
	}


func _world_for(objects: Dictionary) -> Dictionary:
	var built := World.build(JSON.stringify(_level(objects)), {"tilemaps": {}})
	check(built.ok, "Invented placements compile: " + str(built.get("error", "")))
	return built.get("world", {})


func _degrades(code: String, options: Dictionary) -> bool:
	var built := World.build(
		JSON.stringify(_level({"one": _place(code, 200, 200, options)})), {"tilemaps": {}}
	)
	return built.ok and built.world.entities[0].code == "?" + code


func _place(code: String, x: int, y: int, options: Dictionary = {}) -> Dictionary:
	var result := {"A": code, "X": x, "Y": y}
	result.merge(options, true)
	return result


func _by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	check(false, "Expected placement exists: " + id)
	return {}


func _shots(state: Dictionary, code: String) -> Array:
	return state.entities.filter(
		func(entity: Dictionary) -> bool: return entity.code == code and entity.status == 1
	)


## A player standing on a long floor at (x, 300) facing right.
func _stand(state: Dictionary, world: Dictionary, x: int, ticks: int = 3) -> void:
	state.x = x * S
	state.y = 300 * S - S / 16
	state.vx = 0
	state.vy = 0
	state.facing = 1
	for _tick in ticks:
		Sim.advance(state, 0, world)


func _floor() -> Dictionary:
	return _place("p2", 1000, 316, {"E1": "2000"})


func _leaf_checks() -> void:
	check(Hits.FIRE == 7 and Hits.ICE == 8, "Fire and ice strike kinds are 7 and 8")
	check(
		(
			Elements.AMMO_SEED == Moves.SEED
			and Elements.AMMO_FIRE == Moves.HEAT
			and Elements.AMMO_ICE == Moves.COLD
		),
		"Element ammunition kinds equal the movement module's kinds"
	)
	check(Elements.of_ammo(Moves.HEAT) == Elements.FIRE, "Heat ammunition fires fire")
	check(Elements.of_ammo(Moves.COLD) == Elements.ICE, "Cold ammunition fires ice")
	check(Elements.of_ammo(Moves.SEED) == Elements.NONE, "Seeds are no element")
	check(Elements.ammo_of(Elements.ICE) == Moves.COLD, "Ice is loaded as cold ammunition")
	var expected := {
		3: [Moves.HEAT, 3],
		4: [Moves.HEAT, 1],
		5: [Moves.HEAT, 9],
		6: [Moves.COLD, 3],
		7: [Moves.COLD, 1],
		8: [Moves.COLD, 9]
	}
	for form: int in expected:
		check(Elements.melon_ammo(form) == expected[form], "Melon form %d ammunition" % form)
	check(Elements.melon_ammo(2).is_empty(), "A seed melon is no element melon")
	check(Elements.melon_ammo(9).is_empty(), "Unknown melon forms load nothing")
	check(Elements.bubble_ammo(Elements.ICE) == [Moves.COLD, 3], "A cold bubble loads three ice")
	check(Elements.opposite(Elements.FIRE) == Elements.ICE, "Ice is the opposite of fire")


func _melon_checks() -> void:
	check(not _degrades("o25", {"F": 5}), "A fire melon is built")
	check(not _degrades("o25", {"F": 6}), "An ice melon is built")
	check(_degrades("o25", {"F": 9}), "An unknown melon form degrades")
	var world := _world_for(
		{
			"floor": _floor(),
			"melon": _place("o25", 450, 284, {"F": 5}),
			"target": _place("e4", 650, 284)
		}
	)
	var state := State.create(world)
	_stand(state, world, 400)
	var melon := _by_id(state, "melon")
	var target := _by_id(state, "target")
	check(melon.status == Registry.ACTIVE, "The fire melon activates on screen")
	Sim.advance(state, Moves.InputBits.USE, world)
	for _tick in 30:
		Sim.advance(state, 0, world)
	check(melon.status == Registry.DEFEATED, "The tongue eats the fire melon")
	check(
		state.move_ammo == Moves.HEAT and state.move_ammo_count == 9,
		"The large fire melon loads nine fire shots"
	)
	target.x = 520 * S
	Sim.advance(state, Moves.InputBits.USE, world)
	check(state.move_ammo_count == 8, "One press spends one fire shot")
	Sim.advance(state, Moves.InputBits.USE, world)
	check(_shots(state, "fire_shot").size() == 1, "A held press does not repeat fire")
	for _tick in 6:
		Sim.advance(state, 0, world)
	check(target.status == Registry.DEFEATED, "The fire shot burns the walker in its path")


func _shot_checks() -> void:
	var world := _world_for({"floor": _floor()})
	var state := State.create(world)
	_stand(state, world, 300)
	var shot := Shot.spawn(state, world, Elements.ICE, 400 * S, 200 * S, 0)
	check(not shot.is_empty() and shot.code == "ice_shot", "An ice request becomes an ice shot")
	check(shot.x == 384 * S and shot.y == 200 * S, "The shot starts 16 px behind the mouth")
	check(shot.vx == 768 * 60 and shot.vy == 0, "The shot flies at 768 px/s")
	var up := Shot.spawn(state, world, Elements.FIRE, 400 * S, 200 * S, -90000)
	check(up.x == 400 * S and up.y == 216 * S and up.vy == -768 * 60, "An upward shot rises")
	var lived := 0
	while shot.status == 1 and lived < 40:
		Sim.advance(state, 0, world)
		lived += 1
	check(lived == Shot.LIFE_TICKS + 1, "A shot lives 0.3 s")
	check(shot.x == 384 * S + 768 * 60 * Shot.LIFE_TICKS, "It travels 0.3 s at full speed")


func _freeze_checks() -> void:
	var world := _world_for({"floor": _floor(), "walker": _place("e4", 500, 284)})
	var state := State.create(world)
	_stand(state, world, 300)
	var walker := _by_id(state, "walker")
	check(walker.status == Registry.ACTIVE, "The walker activates")
	var type := Registry.lookup("e4")
	type.hit(walker, state, world, Hits.ICE, walker.x)
	check(walker.frozen == 1 and walker.thaw_ticks == 0, "Ice freezes the walker for good")
	check(walker.vy == Reactions.HOP, "A body frozen on the ground hops")
	for _tick in 40:
		Sim.advance(state, 0, world)
	var x: int = walker.x
	for _tick in 30:
		Sim.advance(state, 0, world)
	check(walker.x == x and walker.vx == 0, "A frozen walker stays put")
	check(walker.status == Registry.ACTIVE, "A frozen walker waits")
	type.hit(walker, state, world, Hits.ICE, walker.x)
	check(walker.frozen == 1, "Ice on ice changes nothing")
	# Walking into it from the side shatters it without hurting.
	state.x = walker.x - 20 * S
	state.y = walker.y + 16 * S - S / 16
	state.invulnerable = 0
	Sim.advance(state, 0, world)
	check(walker.status == Registry.DEFEATED, "Touching a frozen body shatters it")
	check(state.invulnerable == 0, "A frozen body does not hurt")
	# A stomp on a frozen body bounces the player and shatters it.
	var world2 := _world_for({"floor": _floor(), "walker": _place("e4", 500, 284)})
	var state2 := State.create(world2)
	_stand(state2, world2, 300)
	var other := _by_id(state2, "walker")
	type.hit(other, state2, world2, Hits.ICE, other.x)
	for _tick in 40:
		Sim.advance(state2, 0, world2)
	state2.x = other.x
	state2.y = other.y - 13 * S
	state2.vy = 300 * 60
	state2.on_floor = 0
	Sim.advance(state2, 0, world2)
	check(other.status == Registry.DEFEATED, "A stomp shatters the frozen body")
	check(state2.vy < 0, "A stomp on a frozen body bounces the player")
	# Fire on a frozen body burns it.
	var world3 := _world_for({"floor": _floor(), "walker": _place("e4", 500, 284)})
	var state3 := State.create(world3)
	_stand(state3, world3, 300)
	var third := _by_id(state3, "walker")
	type.hit(third, state3, world3, Hits.ICE, third.x)
	type.hit(third, state3, world3, Hits.FIRE, third.x)
	check(third.status == Registry.DEFEATED, "Fire burns a frozen body")


func _thaw_checks() -> void:
	var world := _world_for({"floor": _floor(), "flyer": _place("e14", 500, 200, {"F": 1})})
	var state := State.create(world)
	_stand(state, world, 300)
	var flyer := _by_id(state, "flyer")
	check(flyer.status == Registry.ACTIVE, "The hanging flyer activates")
	Registry.lookup("e14").hit(flyer, state, world, Hits.ICE, flyer.x)
	check(flyer.frozen == 1 and flyer.thaw_ticks == Elements.THAW_TICKS, "The flyer thaws later")
	var y: int = flyer.y
	for _tick in 20:
		Sim.advance(state, 0, world)
	check(flyer.y > y, "A frozen flyer falls")
	for _tick in Elements.THAW_TICKS - 20 - Elements.SHAKE_TICKS:
		Sim.advance(state, 0, world)
	check(Reactions.shaking(flyer), "The ice shakes in its last second")
	for _tick in Elements.SHAKE_TICKS:
		Sim.advance(state, 0, world)
	check(flyer.frozen == 0 and flyer.thaw_ticks == 0, "The flyer thaws after eight seconds")


func _immune_checks() -> void:
	var world := _world_for(
		{
			"floor": _floor(),
			"thief": _place("e10", 500, 284),
			"giant": _place("e24", 700, 268, {"M": 2}),
			"petal_stem": _place("e18", 900, 284)
		}
	)
	var state := State.create(world)
	_stand(state, world, 600)
	var thief := _by_id(state, "thief")
	var giant := _by_id(state, "giant")
	for entity: Dictionary in [thief, giant]:
		check(entity.status == Registry.ACTIVE, "Placed enemy activates: " + entity.code)
	Shot.spawn(state, world, Elements.FIRE, thief.x - 10 * S, thief.y, 0)
	Shot.spawn(state, world, Elements.FIRE, giant.x - 10 * S, giant.y, 0)
	for _tick in 3:
		Sim.advance(state, 0, world)
	check(thief.status == Registry.ACTIVE and thief.get("frozen", 0) == 0, "Fire passes the thief")
	check(giant.status == Registry.ACTIVE, "Fire does not burn the large soft walker")
	Shot.spawn(state, world, Elements.ICE, giant.x - 10 * S, giant.y, 0)
	for _tick in 3:
		Sim.advance(state, 0, world)
	check(giant.frozen == 1, "Ice freezes the large soft walker")


func _bubble_checks() -> void:
	var options := {"E1": "3", "E2": "0", "E3": "1", "E4": "0"}
	check(not _degrades("e16", options), "The bubble is built")
	check(_degrades("e16", {"F": 5}), "An unknown bubble form degrades")
	check(_degrades("e16", {"E1": "20000"}), "A huge leap degrades")
	var world := _world_for(
		{
			"bubble": _place("e16", 500, 400, options),
			"cold": _place("e16", 900, 400, {"E1": "2", "E2": "0", "E3": "1", "E4": "0", "F": 3})
		}
	)
	var state := State.create(world)
	state.x = 600 * S
	state.y = 300 * S
	var bubble := _by_id(state, "bubble")
	var cold := _by_id(state, "cold")
	check(bubble.home_y == 416 * S and bubble.hidden == 1, "It waits unseen 16 px below its place")
	state.invulnerable = 60
	var top: int = bubble.y
	var hidden_again := false
	var shown := false
	for _tick in 120:
		Sim.advance(state, 0, world)
		state.x = 600 * S
		state.y = 300 * S
		state.vx = 0
		state.vy = 0
		state.invulnerable = 60
		top = mini(top, bubble.y)
		shown = shown or bubble.hidden == 0
		hidden_again = hidden_again or (shown and bubble.hidden == 1)
	check(shown, "The bubble leaps into view")
	check(
		top >= 416 * S - 112 * S and top <= 416 * S - 111 * S,
		"It slows to a stop 32 x E1 + 16 px above home"
	)
	check(hidden_again, "It drops home and hides again")
	# Swallowing a burning bubble loads three fire shots.
	var ammo_state := State.create(world)
	var target := _by_id(ammo_state, "bubble")
	target.status = Registry.ACTIVE
	target.hidden = 0
	ammo_state.move_action = Moves.TONGUE
	ammo_state.move_tongue_phase = Moves.TONGUE_OUT
	check(Registry.lookup("e16").tongue(target, ammo_state, world) == 1, "The tongue catches it")
	check(
		ammo_state.move_ammo == Moves.HEAT and ammo_state.move_ammo_count == 3,
		"A burning bubble loads three fire shots"
	)
	var cold_state := State.create(world)
	var cold_target := _by_id(cold_state, "cold")
	cold_target.status = Registry.ACTIVE
	cold_target.hidden = 0
	cold_state.move_action = Moves.TONGUE
	cold_state.move_tongue_phase = Moves.TONGUE_OUT
	Registry.lookup("e16").tongue(cold_target, cold_state, world)
	check(cold_state.move_ammo == Moves.COLD, "A cold bubble loads ice")
	# Fire only puts out the cold form; ice only freezes the burning forms.
	var type := Registry.lookup("e16")
	type.hit(bubble, state, world, Hits.FIRE, 0)
	check(bubble.status == Registry.ACTIVE, "Fire passes a burning bubble")
	type.hit(cold, state, world, Hits.ICE, 0)
	check(cold.frozen == 0, "Ice passes a cold bubble")
	type.hit(cold, state, world, Hits.FIRE, 0)
	check(cold.status == Registry.DEFEATED, "Fire puts out a cold bubble")
	# A frozen bubble falls and shatters when it lands.
	var land_world := _world_for(
		{
			"floor": _place("p2", 1000, 516, {"E1": "2000"}),
			"bubble": _place("e16", 500, 300, options)
		}
	)
	var land_state := State.create(land_world)
	land_state.x = 600 * S
	land_state.y = 200 * S
	var lander := _by_id(land_state, "bubble")
	lander.status = Registry.ACTIVE
	lander.hidden = 0
	type.hit(lander, land_state, land_world, Hits.ICE, 0)
	check(lander.frozen == 1 and lander.thaw_ticks == Elements.THAW_TICKS, "Ice freezes a bubble")
	for _tick in 90:
		Sim.advance(land_state, 0, land_world)
		land_state.x = 600 * S
		land_state.y = 200 * S
	check(lander.status == Registry.DEFEATED, "A frozen bubble shatters when it lands")


func _lamp_checks() -> void:
	var world := _world_for(
		{"fire_lamp": _place("d25", 500, 200, {"F": 2}), "ice_lamp": _place("d26", 700, 200)}
	)
	var state := State.create(world)
	state.x = 600 * S
	state.y = 300 * S
	var fire_lamp := _by_id(state, "fire_lamp")
	var ice_lamp := _by_id(state, "ice_lamp")
	check(fire_lamp.lamp_lit == 0 and ice_lamp.lamp_lit == 1, "Lamps start as placed")
	Shot.spawn(state, world, Elements.FIRE, fire_lamp.x - 10 * S, fire_lamp.y, 0)
	Shot.spawn(state, world, Elements.FIRE, ice_lamp.x - 10 * S, ice_lamp.y, 0)
	for _tick in 2:
		Sim.advance(state, 0, world)
	check(fire_lamp.lamp_lit == 1, "Fire lights a fire lamp")
	check(ice_lamp.lamp_lit == 0, "Fire puts out an ice lamp")
	for _tick in 30:
		Sim.advance(state, 0, world)
	Shot.spawn(state, world, Elements.ICE, fire_lamp.x - 10 * S, fire_lamp.y, 0)
	Shot.spawn(state, world, Elements.ICE, ice_lamp.x - 10 * S, ice_lamp.y, 0)
	for _tick in 2:
		Sim.advance(state, 0, world)
	check(fire_lamp.lamp_lit == 0, "Ice puts out a fire lamp")
	check(ice_lamp.lamp_lit == 1, "Ice lights an ice lamp")
	var lamp_type := Registry.lookup("d25")
	check(not lamp_type.has_method("hit"), "Eggs, seeds and spat bodies still pass lamps")


func _cloud_checks() -> void:
	var world := _world_for({"cloud": _place("o8", 500, 200, {"E1": "1", "E2": "3", "E3": "1"})})
	var state := State.create(world)
	state.x = 400 * S
	state.y = 300 * S
	var cloud := _by_id(state, "cloud")
	check(cloud.phase == 0, "The cloud starts hidden")
	Registry.lookup("o8").hit(cloud, state, world, Hits.EGG, 0)
	check(cloud.phase == 2, "An egg only reveals a hidden cloud")
	var world2 := _world_for({"cloud": _place("o8", 500, 200, {"E1": "1", "E2": "3", "E3": "1"})})
	var state2 := State.create(world2)
	state2.x = 400 * S
	state2.y = 300 * S
	var hidden := _by_id(state2, "cloud")
	Shot.spawn(state2, world2, Elements.ICE, hidden.x - 30 * S, hidden.y, 0)
	for _tick in 3:
		Sim.advance(state2, 0, world2)
	check(hidden.phase == 3, "Ice breath opens a hidden cloud at once")


func _launcher_checks() -> void:
	var world := _world_for({"floor": _floor(), "launcher": _place("e37", 500, 284)})
	var state := State.create(world)
	_stand(state, world, 300)
	var launcher := _by_id(state, "launcher")
	check(launcher.status == Registry.ACTIVE, "The launcher activates")
	var type := Registry.lookup("e37")
	check(not type.has_method("hit"), "Eggs keep meeting only the launcher's solid box")
	var shot := Shot.spawn(state, world, Elements.FIRE, launcher.x - 20 * S, launcher.y, 0)
	type.projectile_contact(launcher, shot, state, world)
	check(launcher.frozen == 0, "Fire does not freeze the launcher")
	var ice := Shot.spawn(state, world, Elements.ICE, launcher.x - 20 * S, launcher.y, 0)
	type.projectile_contact(launcher, ice, state, world)
	check(launcher.frozen == 1 and type.solid_box(launcher).is_empty(), "Ice freezes it hollow")
	var before: int = state.entities.size()
	for _tick in 400:
		Sim.advance(state, 0, world)
		state.x = 300 * S
	check(
		(
			state
			. entities
			. filter(func(e: Dictionary) -> bool: return e.code == "enemy_shot")
			. is_empty()
		),
		"A frozen launcher never fires"
	)
	check(state.entities.size() <= before, "Nothing new appears near a frozen launcher")
	state.x = launcher.x - 20 * S
	state.y = launcher.y + 16 * S - S / 16
	Sim.advance(state, 0, world)
	check(launcher.status == Registry.DEFEATED, "Touching a frozen launcher shatters it")


func _snapshot_checks() -> void:
	var world := _world_for(
		{
			"floor": _floor(),
			"walker": _place("e4", 500, 284),
			"bubble": _place("e16", 700, 400, {"E1": "3", "E2": "4", "E3": "2", "E4": "0"})
		}
	)
	var state := State.create(world)
	_stand(state, world, 300)
	var walker := _by_id(state, "walker")
	Registry.lookup("e4").hit(walker, state, world, Hits.ICE, walker.x)
	Shot.spawn(state, world, Elements.FIRE, 600 * S, 280 * S, 0)
	Shot.spawn(state, world, Elements.ICE, 600 * S, 280 * S, 180000)
	Sim.advance(state, 0, world)
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, state.identity, world)
	check(
		decoded.ok, "A state with frozen bodies and shots decodes: " + str(decoded.get("error", ""))
	)
	check(decoded.ok and Snapshot.encode(decoded.state) == bytes, "It round trips byte for byte")
	if not decoded.ok:
		return
	var restored: Dictionary = decoded.state
	for _tick in 20:
		Sim.advance(state, 0, world)
		Sim.advance(restored, 0, world)
	check(Snapshot.encode(state) == Snapshot.encode(restored), "Restored play repeats exactly")
	walker.frozen = 0
	walker.thaw_ticks = 5
	check(not Snapshot.valid_state(state), "An unfrozen body cannot carry a thaw count")
	walker.thaw_ticks = 0
	walker.frozen = 2
	check(not Snapshot.valid_state(state), "The frozen flag is binary")
	walker.frozen = 1


## Every enemy that declares reactions burns or freezes as declared, a frozen one
## holds still, and touching it shatters it.
func _every_type_checks() -> void:
	var skip := ["e16", "e37", "d25", "d26", "o8", "enemy_runner", "enemy_shot", "enemy_petal"]
	for code: String in Registry.codes():
		var type: Script = Registry.lookup(code)
		var declared := int(type.get_script_constant_map().get("ELEMENT_REACTIONS", 0))
		if not declared or code in skip:
			continue
		for kind: int in [Hits.FIRE, Hits.ICE]:
			var world := _world_for(
				{"floor": _floor(), "it": _place(code, 500, 270, TYPE_OPTIONS.get(code, {}))}
			)
			var state := State.create(world)
			_stand(state, world, 380, 4)
			var entity := _by_id(state, "it")
			if entity.status != Registry.ACTIVE:
				check(false, "Reacting code activates: " + code)
				continue
			var flags := declared
			if type.has_method("element_reactions"):
				flags = type.element_reactions(entity)
			type.hit(entity, state, world, kind, entity.x)
			if kind == Hits.FIRE:
				var burnt: bool = entity.status == Registry.DEFEATED
				check(burnt == bool(flags & Elements.BURNS), "Fire burns as declared: " + code)
				continue
			check(
				entity.frozen == int(bool(flags & Elements.FREEZES)),
				"Ice freezes as declared: " + code
			)
			if not entity.frozen:
				continue
			var x: int = entity.x
			for _tick in 30:
				Sim.advance(state, 0, world)
				state.x = 380 * S
			check(entity.x == x, "A frozen body does not walk: " + code)
			check(entity.status == Registry.ACTIVE, "A frozen body waits: " + code)
			var box: Array = type.bounds(entity)
			state.x = entity.x + box[0] - 8 * S
			state.y = entity.y + box[3] - S / 16
			state.invulnerable = 0
			state.vx = 24 * 60
			for _tick in 3:
				Sim.advance(state, Moves.InputBits.RIGHT, world)
			check(entity.status == Registry.DEFEATED, "Touch shatters the frozen body: " + code)
			check(state.invulnerable == 0, "A frozen body does not hurt: " + code)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)
