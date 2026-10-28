extends SceneTree
## Fast checks for the flower appearance and hanging plant forms on invented placements.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const World = preload("res://src/sim/world.gd")
const Sim = preload("res://src/sim/step.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const S := preload("res://src/sim/units.gd").SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	flower_checks()
	hanging_checks()
	print("ENEMY_VARIANTS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)


func build(objects: Dictionary, start_x: int) -> Dictionary:
	var code := JSON.stringify(
		{
			"version": "s3.8.0",
			"name": "Variants",
			"author": "Eggshell",
			"desc": "",
			"startpoint": {"map": 1, "X": start_x, "Y": 200},
			"maps": {"map1": {"width": 1280, "height": 384, "objects": objects}}
		}
	)
	var built := World.build(code, {"tilemaps": {}})
	check(built.ok, "Variant level compiles")
	return built.get("world", {})


## Ceiling cells cover x 0..639 and y 0..63; the floor starts at y 288.
func add_terrain(world: Dictionary) -> void:
	var cells := PackedInt32Array()
	cells.resize(40 * 12)
	cells.fill(-1)
	for column in 40:
		cells[40 * 9 + column] = 0
		if column < 20:
			cells[column] = 0
			cells[40 + column] = 0
	var layer := {
		"name": "unit",
		"layer": "layer1",
		"size": 32,
		"width": 40,
		"height": 12,
		"cells": cells,
		"bounds": {0: [0, 0, 32 * S, 32 * S]},
		"polygons": {0: PackedInt64Array([0, 0, 32 * S, 0, 32 * S, 32 * S, 0, 32 * S])},
		"solid": true,
		"water": false
	}
	world.layers = [layer]
	for index: Variant in world.maps:
		world.maps[index].layers = [layer]


func entity(state: Dictionary, id: String) -> Dictionary:
	for placed: Dictionary in state.entities:
		if placed.id == id:
			return placed
	return {}


func flower_checks() -> void:
	var world := build({"flower": {"A": "e3", "X": 300, "Y": 200, "F": 1}}, 200)
	if world.is_empty():
		return
	var state := State.create(world)
	var flower := entity(state, "flower")
	check(flower.code == "e3" and flower.variant == 1, "The second flower colour is saved")
	check(Registry.valid(flower), "The second flower colour is valid state")
	var type := Registry.lookup("e3")
	check(type.view_state(flower, state).animation == "walk", "A flower walks in its colour")
	flower.mode = 1
	check(type.view_state(flower, state).animation == "turn", "A turning flower shows its turn")


func hanging_checks() -> void:
	var world := build(
		{
			"hanging": {"A": "e5", "X": 400, "Y": 84, "F": 1},
			"open": {"A": "e5", "X": 800, "Y": 84, "F": 1}
		},
		600
	)
	if world.is_empty():
		return
	add_terrain(world)
	var state := State.create(world)
	Sim.advance(state, 0, world)
	var hanging := entity(state, "hanging")
	var open := entity(state, "open")
	check(hanging.status == Registry.ACTIVE, "The hanging plant activates on screen")
	check(Plant.hanging(hanging), "A plant under a ceiling keeps the hanging form")
	check(not Plant.hanging(open), "A plant with no ceiling becomes the ground form")
	check(
		Registry.lookup("e5").view_state(hanging, state).get("flip_y", 0) == 1,
		"The hanging stem draws flipped"
	)
	check(
		not Registry.lookup("e5").view_state(open, state).has("flip_y"),
		"The ground form draws upright"
	)
	for _tick in 90:
		Sim.advance(state, 0, world)
	check(hanging.y == 84 * S and hanging.vy == 0, "The hanging stem stays pinned")
	check(absi(open.y - 272 * S) < S and open.vy == 0, "The ground form falls to the floor")
	check(hanging.mode != 0 and hanging.head_dy > 0, "The hanging head reaches downward")
	var head := Plant.head_box(hanging)
	check((head[1] + head[3]) / 2 > hanging.y + 10 * S, "The hanging head sits below its pivot")
	var bytes := Snapshot.encode(state)
	var decoded := Snapshot.decode(bytes, world.identity, world)
	check(decoded.ok, "Hanging and reverted plants save and restore")
	if decoded.ok:
		check(Snapshot.encode(decoded.state) == bytes, "The restored plants are byte exact")
		check(
			(
				Plant.hanging(entity(decoded.state, "hanging"))
				and not Plant.hanging(entity(decoded.state, "open"))
			),
			"The restored forms are kept"
		)
