extends SceneTree
## Remembered terrain answers equal fresh ones: probe boxes, and the push-out search of
## Collision.prepare with and without solid rows nearby. Invented geometry only; no levels,
## scenes or assets.

const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const S := 3600
const SIZE := 24
var checks := 0
var failures := 0
var seed := 31337


class Block:
	extends RefCounted
	const SOLID := 1

	static func bounds(_entity: Dictionary) -> Array:
		return [-16 * 3600, -16 * 3600, 16 * 3600, 16 * 3600]

	static func solid_box(entity: Dictionary) -> Array:
		if entity.status != 1:
			return []
		return [
			entity.x - 16 * 3600, entity.y - 16 * 3600, entity.x + 16 * 3600, entity.y + 16 * 3600
		]


class Dispatch:
	extends RefCounted

	static func lookup(_code: String) -> Script:
		return Block


func _initialize() -> void:
	probe_checks()
	escape_checks()
	print("TERRAIN_MEMO_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func next(limit: int) -> int:
	seed = (seed * 1103515245 + 12345) % 2147483648
	return (seed >> 16) % limit


## A SIZE x SIZE map of 32 px cells: walls, slopes and holes. Same layers for both worlds.
func layers() -> Array:
	var square := PackedInt64Array([0, 0, 32 * S, 0, 32 * S, 32 * S, 0, 32 * S])
	var slope := PackedInt64Array([0, 32 * S, 32 * S, 0, 32 * S, 32 * S])
	var cells := PackedInt32Array()
	cells.resize(SIZE * SIZE)
	for index in cells.size():
		var pick := next(10)
		cells[index] = 0 if pick < 4 else (1 if pick < 5 else -1)
	return [
		{
			"size": 32,
			"width": SIZE,
			"height": SIZE,
			"cells": cells,
			"bounds": {0: World.polygon_bounds(square), 1: World.polygon_bounds(slope)},
			"polygons": {0: square, 1: slope},
			"rectangles": {0: true},
			"solid": true,
			"water": false
		}
	]


func worlds() -> Array:
	var shared := layers()
	var plain := {"layers": shared, "bridges": [], "width": SIZE * 32 * S, "height": SIZE * 32 * S}
	var remembered := plain.duplicate()
	remembered.terrain_hits = {}
	remembered.terrain_escapes = {}
	return [plain, remembered]


func probe_checks() -> void:
	var pair := worlds()
	var boxes := []
	for index in 300:
		var x := next(SIZE * 32) * S
		var y := next(SIZE * 32) * S
		boxes.append([x, y, x + next(40) * S, y + next(40) * S])
	# Twice: the second pass answers from memory.
	for round in 2:
		for box: Array in boxes:
			check(
				(
					World.overlaps_box(pair[0], box[0], box[1], box[2], box[3])
					== World.overlaps_box(pair[1], box[0], box[1], box[2], box[3])
				),
				"Remembered terrain answer: %s" % [box]
			)
	check(not pair[1].terrain_hits.is_empty(), "Answers are remembered")


func escape_checks() -> void:
	var pair := worlds()
	var bounds := [-14 * S, -30 * S, 14 * S, 0]
	var starts := []
	for index in 200:
		starts.append([next(SIZE * 32) * S + next(S), next(SIZE * 32) * S, next(3) * 1000])
	# Without solid rows, then with solid rows filed near some starts.
	for with_solids in [false, true]:
		var blocks := []
		if with_solids:
			for index in 40:
				var start: Array = starts[index * 5]
				blocks.append(
					{
						"code": "block",
						"id": str(index),
						"token": index + 1,
						"status": 1,
						"x": start[0] + (next(80) - 40) * S,
						"y": start[1] + (next(80) - 40) * S
					}
				)
		for world: Dictionary in pair:
			world.erase("solids_step")
			if with_solids:
				var state := {"x": 0, "y": 0, "frame": 1, "entities": blocks}
				Collision.begin_step(state, world, Dispatch)
		for round in 2:
			for start: Array in starts:
				var results := []
				for world: Dictionary in pair:
					var body := {"x": start[0], "y": start[1], "vx": 0, "vy": start[2]}
					var ok := Collision.prepare(body, world, bounds)
					results.append([ok, body.x, body.y, body.vy])
				check(
					results[0] == results[1],
					"Remembered escape equals the search: %s %s" % [start, results]
				)
	check(not pair[1].terrain_escapes.is_empty(), "Escapes are remembered")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
