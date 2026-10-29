extends SceneTree
## Invented placements exercise motion, contact and restored futures through the simulation.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Grid = preload("res://src/sim/entity_grid.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	fish_air_motion()
	fish_water_launch()
	burst_armor(false)
	burst_armor(true)
	for reverse: bool in [false, true]:
		armor_group(reverse, false)
		armor_group(reverse, true)
		armor_tween_age(reverse)
		fish_group(reverse)
		fish_group(reverse, 0, true)
	for blocker: int in [1, 2, 3]:
		fish_group(false, blocker)
	soft_group_selection()
	birth_lifecycle()
	print("FISH_ARMORED_CONTACTS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func fixture(objects: Dictionary, activate: bool = true) -> Dictionary:
	var world := {
		"identity": "invented fish and armor contacts".sha256_text(),
		"spawn_x": 64 * S,
		"spawn_y": 300 * S,
		"spawn_facing": 1,
		"map_index": 1,
		"initial_map": 1,
		"map_count": 1,
		"flowers_target": 0,
		"redcoins_target": 0,
		"width": 4096 * S,
		"height": 1024 * S,
		"layers": []
	}
	check(Registry.compile_map(objects, world).ok, "Invented placements compile")
	world.maps = {1: world.duplicate()}
	var state := State.create(world)
	Registry.spawn_map(state, world)
	if activate:
		for entity: Dictionary in state.entities:
			entity.status = Registry.ACTIVE
			if entity.has("started"):
				entity.started = 1
	return {"world": world, "state": state}


func by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	return {}


func fish_air_motion() -> void:
	var unit := fixture({"fish": {"A": "e20", "X": 700, "Y": 180, "F": 2}})
	var fish := by_id(unit.state, "fish")
	fish.mode = 4
	fish.vx = -128 * 60
	fish.vy = -800 * 60
	var y: int = fish.y
	Sim.advance(unit.state, 0, unit.world)
	check(fish.vy == -800 * 60 + 2048, "An airborne fish gains one tick of dry gravity")
	check(
		fish.y == y - 800 * 60 + 1024,
		"An airborne fish moves by the mean of its old and new vertical speed"
	)
	restored_future(unit)


func fish_water_launch() -> void:
	var unit := fixture({"fish": {"A": "e20", "X": 700, "Y": 304, "F": 2}})
	water(unit, 300)
	var fish := by_id(unit.state, "fish")
	fish.water = 1
	fish.home_y = fish.y
	fish.fish_left = 232 * S
	fish.fish_right = -24 * S
	fish.x = fish.home_x - 63 * S
	fish.vx = -128 * 60
	Sim.advance(unit.state, 0, unit.world)
	check(
		fish.mode == 4 and fish.vy == -800 * 60,
		"The arc threshold sees this frame's horizontal motion"
	)
	check(fish.water == 1, "Starting an arc does not clear the water event state")
	Sim.advance(unit.state, 0, unit.world)
	check(
		fish.vy == -800 * 60 and fish.water == 1, "The first arc body step still uses water gravity"
	)
	Sim.advance(unit.state, 0, unit.world)
	check(
		fish.vy == -800 * 60 and fish.water == 0,
		"The origin exit event updates gravity after motion"
	)
	Sim.advance(unit.state, 0, unit.world)
	check(fish.vy == -800 * 60 + 2048, "The next arc body step uses dry gravity")
	restored_future(unit)


func water(unit: Dictionary, surface: int = 0) -> void:
	unit.world.layers = [
		{
			"name": "invented_water",
			"layer": "layer1",
			"size": 2048,
			"width": 2,
			"height": 1,
			"cells": PackedInt32Array([0, 0]),
			"bounds": {0: [0, surface * S, 2048 * S, 2048 * S]},
			"polygons":
			{
				0:
				PackedInt64Array(
					[0, surface * S, 2048 * S, surface * S, 2048 * S, 2048 * S, 0, 2048 * S]
				)
			},
			"solid": false,
			"water": true
		}
	]
	unit.world.maps[1].layers = unit.world.layers


func burst_armor(armor_first: bool) -> void:
	var armor_id := "a" if armor_first else "z"
	var objects := {}
	var armor_source := {"A": "e11", "X": 480, "Y": 284, "F": 3}
	if armor_first:
		objects[armor_id] = armor_source
	objects["burst"] = {"A": "e23", "X": 400, "Y": 284}
	if not armor_first:
		objects[armor_id] = armor_source
	objects["floor"] = {"A": "p2", "X": 500, "Y": 316, "E1": "1024"}
	var unit := fixture(objects)
	var soft := by_id(unit.state, "burst")
	var armor := by_id(unit.state, armor_id)
	check(
		(unit.state.entities.find(armor) < unit.state.entities.find(soft)) == armor_first,
		"The fixture really reverses the armor and burst dispatch order"
	)
	var type: Script = Registry.lookup("e23")
	soft.mode = type.SQUASH
	soft.timer = 1
	var x: int = armor.x
	Grid.min_queries = 0
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.nearby(unit.state, unit.world, [464 * S, 268 * S, 496 * S, 300 * S])
	Sim.advance(unit.state, 0, unit.world)
	check(soft.status == Registry.DEFEATED, "The soft body bursts")
	check(armor.vx == 448 * 60, "The burst reaches nearby armor, in either dispatch order")
	check(armor.x == x, "Burst knockback starts after this tick's body motion")
	check(armor.vy < 0, "Standing armor hops when knocked away")
	Sim.advance(unit.state, 0, unit.world)
	check(armor.x > x, "Knocked armor moves away instead of remaining in the player's path")
	restored_future(unit)
	Grid.min_queries = 4


func armor_group(reverse: bool, older_right: bool) -> void:
	var left_source := {"A": "e11", "X": 320, "Y": 284, "F": 3}
	var right_source := {"A": "e11", "X": 480, "Y": 284, "F": 3}
	var objects := {}
	objects["right" if reverse else "left"] = right_source if reverse else left_source
	objects["burst"] = {"A": "e23", "X": 400, "Y": 284}
	objects["left" if reverse else "right"] = left_source if reverse else right_source
	objects["wall"] = {"A": "o9", "X": 448, "Y": 272}
	objects["floor"] = {"A": "p2", "X": 500, "Y": 316, "E1": "1024"}
	var unit := fixture(objects)
	var left := by_id(unit.state, "left")
	var right := by_id(unit.state, "right")
	left.birth_frame = 20 if older_right else 10
	right.birth_frame = 10 if older_right else 20
	unit.state.frame = 30
	var soft := by_id(unit.state, "burst")
	soft.mode = Registry.lookup("e23").SQUASH
	soft.timer = 1
	Sim.advance(unit.state, 0, unit.world)
	check(
		(right.knock_ticks < 0) == (not older_right),
		"The first created knocked body's sign controls the group's wall filter, not table order"
	)
	check(right.vx == 448 * 60, "A rebound changes the tween, not this frame's assigned velocity")
	check(
		right.vy == (-384 if older_right else -184) * 60,
		"The hop reads the rebound tween after the two-stage wall probe"
	)
	restored_future(unit)


func armor_tween_age(reverse: bool) -> void:
	var left_source := {"A": "e11", "X": 320, "Y": 284, "F": 3}
	var right_source := {"A": "e11", "X": 480, "Y": 284, "F": 3}
	var objects := {}
	objects["right" if reverse else "left"] = right_source if reverse else left_source
	objects["left" if reverse else "right"] = left_source if reverse else right_source
	objects["wall"] = {"A": "o9", "X": 448, "Y": 272}
	objects["floor"] = {"A": "p2", "X": 500, "Y": 316, "E1": "1024"}
	var unit := fixture(objects)
	var left := by_id(unit.state, "left")
	var right := by_id(unit.state, "right")
	left.birth_frame = 10
	right.birth_frame = 20
	left.roll_direction = -1
	right.roll_direction = 1
	left.knock_ticks = 9
	right.knock_ticks = 30
	unit.state.frame = 40
	Sim.advance(unit.state, 0, unit.world)
	check(
		right.knock_ticks == 29,
		"The group's oldest tween has aged below the wall threshold, even when it steps last"
	)
	restored_future(unit)


func soft_group_selection() -> void:
	var unit := fixture(
		{
			"armor": {"A": "e11", "X": 480, "Y": 284, "F": 3},
			"burst": {"A": "e23", "X": 400, "Y": 284},
			"older_soft": {"A": "e23", "X": 100, "Y": 284},
			"wall": {"A": "o9", "X": 448, "Y": 272},
			"floor": {"A": "p2", "X": 500, "Y": 316, "E1": "1024"}
		}
	)
	var type: Script = Registry.lookup("e23")
	var older := by_id(unit.state, "older_soft")
	older.birth_frame = 10
	older.mode = type.KNOCKED
	older.slide_from = -448 * 60
	older.slide_total = 60
	older.slide_ticks = 40
	var armor := by_id(unit.state, "armor")
	armor.birth_frame = 20
	unit.state.frame = 30
	var soft := by_id(unit.state, "burst")
	soft.mode = type.SQUASH
	soft.timer = 1
	Sim.advance(unit.state, 0, unit.world)
	check(
		armor.knock_ticks == -90, "An older knocked soft body participates in the family comparison"
	)
	restored_future(unit)


func fish_group(reverse: bool, blocker: int = 0, tied: bool = false) -> void:
	var first_source := {"A": "e20", "X": 700, "Y": 300}
	var second_source := {"A": "e21", "X": 900, "Y": 300}
	var objects := {}
	objects["second" if reverse else "first"] = second_source if reverse else first_source
	objects["first" if reverse else "second"] = first_source if reverse else second_source
	objects["right"] = {"A": "e20", "X": 1100, "Y": 300, "M": 1}
	objects["last"] = {"A": "e20", "X": 600, "Y": 100}
	var unit := fixture(objects)
	var first := by_id(unit.state, "first")
	var second := by_id(unit.state, "second")
	var right := by_id(unit.state, "right")
	first.birth_frame = 10
	second.birth_frame = 10 if tied else 20
	right.birth_frame = 30
	var last := by_id(unit.state, "last")
	if blocker == 1:
		Registry.lookup("e20").tongue(last, unit.state, unit.world)
	elif blocker == 2:
		last.frozen = 1
	else:
		last.status = Registry.DEFEATED
	unit.state.frame = 40
	for fish: Dictionary in [first, second, right]:
		fish.water = 1
		fish.home_y = fish.y
		fish.x += fish.facing * 50 * S
		fish.vx = fish.facing * 128 * 60
	water(unit)
	Sim.advance(unit.state, 0, unit.world)
	var selected := second if tied and reverse else first
	var deferred := first if tied and reverse else second
	check(
		selected.mode == 1 and deferred.mode == 0,
		"Only the first created left-crossing fish turns; tied births preserve creation order"
	)
	check(right.mode == 1, "The right event independently turns its first picked fish")
	Sim.advance(unit.state, 0, unit.world)
	check(deferred.mode == 1, "The second crossing fish turns on the next frame")
	restored_future(unit)


func birth_lifecycle() -> void:
	var unit := fixture(
		{"armor": {"A": "e11", "X": 1500, "Y": 300}, "soft": {"A": "e23", "X": 1600, "Y": 300}},
		false
	)
	var armor := by_id(unit.state, "armor")
	var soft := by_id(unit.state, "soft")
	check(
		armor.status == Registry.QUEUED and soft.status == Registry.QUEUED,
		"Distant births cull before activation"
	)
	unit.state.frame = 20
	unit.state.camera_x = 1000 * S
	Registry.lifecycle(armor, unit.state, unit.world)
	Registry.lifecycle(soft, unit.state, unit.world)
	check(
		armor.birth_frame == 20 and soft.birth_frame == 20,
		"Camera recreation stamps actual birth, not activation"
	)
	check(armor.status == Registry.WAITING, "A recreated body can remain inactive")
	unit.state.frame = 25
	unit.state.camera_x = 1200 * S
	Registry.lifecycle(armor, unit.state, unit.world)
	check(
		armor.status == Registry.ACTIVE and armor.birth_frame == 20,
		"Activation does not replace the earlier creation clock"
	)
	unit.state.frame = 30
	var runtime := Registry.spawn_dynamic(unit.state, unit.world, "e11", 1000 * S, 300 * S, {})
	check(
		not runtime.has("error") and runtime.birth_frame == 30,
		"Runtime birth uses the same saved creation clock"
	)
	var distant := Registry.spawn_dynamic(unit.state, unit.world, "e11", 3000 * S, 300 * S, {})
	check(
		not distant.has("error") and distant.status == Registry.DEFEATED,
		"A distant runtime birth culls before activation and does not become a picked body"
	)
	restored_future(unit)


func restored_future(unit: Dictionary) -> void:
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "The changed actor state has a valid snapshot")
	var decoded := Snapshot.decode(bytes, unit.state.identity, unit.world)
	check(decoded.ok, "The changed actor state restores")
	if not decoded.ok:
		return
	var restored: Dictionary = decoded.state
	var world: Dictionary = unit.world.duplicate(true)
	for _tick in 120:
		Sim.advance(unit.state, 0, unit.world)
		Sim.advance(restored, 0, world)
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(restored),
		"Restoring midway through actor motion preserves its full future"
	)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
