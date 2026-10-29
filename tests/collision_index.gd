extends SceneTree
## The solid index, the terrain chunk cache and the rectangle shortcut give the same
## answers as full scans. Invented geometry only; no levels, scenes or assets.

const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const S := 3600
const BODY := [-12 * S, -28 * S, 12 * S, 0]
var checks := 0
var failures := 0
var seed := 977


class Block:
	extends RefCounted
	const SOLID := 1

	static func bounds(entity: Dictionary) -> Array:
		return [-entity.half, -entity.half, entity.half, entity.half]

	static func solid_box(entity: Dictionary) -> Array:
		if entity.status != 1 or not entity.enabled:
			return []
		return [
			entity.x - entity.half,
			entity.y - entity.half,
			entity.x + entity.half,
			entity.y + entity.half
		]


class Ledge:
	extends RefCounted
	const SOLID := 2

	static func solid_boxes(entity: Dictionary) -> Array:
		if entity.status != 1:
			return []
		return [
			[entity.x - 40 * S, entity.y, entity.x, entity.y + 2 * S],
			[entity.x + 8 * S, entity.y - 30 * S, entity.x + 48 * S, entity.y - 28 * S]
		]


class Dispatch:
	extends RefCounted

	static func lookup(code: String) -> Script:
		return Block if code == "block" else Ledge


func _initialize() -> void:
	solid_index_checks()
	terrain_cache_checks()
	rectangle_checks()
	print("COLLISION_INDEX_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func next(limit: int) -> int:
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed % limit


func solid_index_checks() -> void:
	var entities := []
	for index in 300:
		entities.append(
			{
				"code": "block" if index % 3 else "ledge",
				"id": str(index),
				"token": index + 1,
				"status": 1 if index % 7 else 3,
				"enabled": 1,
				"half": (8 + next(40)) * S,
				"x": next(3000) * S,
				"y": next(800) * S
			}
		)
	var state := {"x": 0, "y": 0, "vx": 0, "vy": 0, "on_floor": 0, "frame": 1, "entities": entities}
	var world := {"layers": [], "bridges": [], "width": 4096 * S, "height": 1024 * S}
	Collision.verify_index = true
	Collision.verify_failures = 0
	Collision.begin_step(state, world, Dispatch)
	compare_queries(state, world, entities, "first step")
	# A solid moves itself during its own dispatch, then the index refiles it.
	var rows: Dictionary = Collision.solid_rows(world)
	for index in range(0, 300, 11):
		var entity: Dictionary = entities[index]
		var row: Dictionary = rows[entity.token]
		Collision.dispatch_begin(world, row)
		entity.x += (next(400) - 200) * S
		entity.y += (next(200) - 100) * S
		var body := {"x": entity.x, "y": entity.y - 60 * S}
		check(
			Collision.overlaps(body, world, BODY) == brute_overlap(body, entities, 0, 0),
			"Query during a dispatch sees the moving solid"
		)
		Collision.dispatch_end(world, row)
	compare_queries(state, world, entities, "after dispatched moves")
	# Removal, and enables inside a solid's bounds, need no refile between dispatches.
	for index in range(0, 300, 5):
		if entities[index].code == "block":
			entities[index].status = 3 if entities[index].status == 1 else 1
		else:
			entities[index].status = 3
	compare_queries(state, world, entities, "after removals")
	check(Collision.verify_failures == 0, "Indexed shapes equal a full scan within the contract")
	# Enabling boxes outside a solid's region without refresh() breaks the contract, and
	# the verifier reports it; refresh() repairs the index.
	var ledge: Dictionary = entities[0]
	ledge.status = 1
	ledge.x += 1500 * S
	Collision.overlaps({"x": ledge.x - 20 * S, "y": ledge.y + 30 * S}, world, BODY)
	Collision.support_in_box(world, ledge.x - 30 * S, ledge.y - S, ledge.x - 10 * S, ledge.y + S)
	check(Collision.verify_failures > 0, "The verifier reports an unrefiled move")
	Collision.verify_failures = 0
	Collision.refresh(world, ledge)
	compare_queries(state, world, entities, "after refresh")
	# The next step keeps the index for the same table and refiles moved rows.
	state.frame = 2
	for index in range(0, 300, 13):
		entities[index].x += 900 * S
	Collision.begin_step(state, world, Dispatch)
	compare_queries(state, world, entities, "second step")
	check(Collision.verify_failures == 0, "Indexed shapes always equal a full scan")
	Collision.verify_index = false


func compare_queries(state: Dictionary, world: Dictionary, entities: Array, label: String) -> void:
	var same := true
	for probe in 400:
		# Probes stay inside the map, clear of its side borders.
		var body := {"x": (64 + next(3200)) * S, "y": next(900) * S, "vx": 0, "vy": 0}
		var dx := (next(5) - 2) * S
		var dy := (next(5) - 2) * S
		same = (
			same
			and (
				Collision.overlaps(body, world, BODY, dx, dy)
				== brute_overlap(body, entities, dx, dy)
			)
		)
		var left: int = body.x + BODY[0]
		var top: int = body.y + BODY[1]
		same = (
			same
			and (
				Collision.support_in_box(world, left, top, left + 20 * S, top + 20 * S)
				== brute_support(entities, [left, top, left + 20 * S, top + 20 * S])
			)
		)
		Collision.floor_at(body, world, BODY)
		Collision.bridges_at(body, world, BODY)
	check(same, "Indexed queries equal full scans: " + label)
	state.x = 0


func boxes(entity: Dictionary) -> Array:
	if entity.code == "block":
		var box := Block.solid_box(entity)
		return [] if box.is_empty() else [box]
	return Ledge.solid_boxes(entity)


func brute_overlap(body: Dictionary, entities: Array, dx: int, dy: int) -> bool:
	var probe := [
		body.x + BODY[0] + dx, body.y + BODY[1] + dy, body.x + BODY[2] + dx, body.y + BODY[3] + dy
	]
	for entity: Dictionary in entities:
		if entity.code == "block" and entity.status == 1:
			for box: Array in boxes(entity):
				if touches(box, probe):
					return true
	return false


func brute_support(entities: Array, probe: Array) -> bool:
	for entity: Dictionary in entities:
		if entity.status != 1:
			continue
		for box: Array in boxes(entity):
			if entity.code == "ledge" and probe[1] > box[1]:
				continue
			if touches(box, probe):
				return true
	return false


func touches(box: Array, probe: Array) -> bool:
	return box[2] >= probe[0] and box[0] <= probe[2] and box[3] >= probe[1] and box[1] <= probe[3]


func terrain_cache_checks() -> void:
	var solid_cells := PackedInt32Array()
	var water_cells := PackedInt32Array()
	var wide_cells := PackedInt32Array()
	for index in 60 * 30:
		solid_cells.append(next(4) - 1 if next(3) == 0 else -1)
		water_cells.append(0 if next(9) == 0 else -1)
	for index in 30 * 15:
		wide_cells.append(next(2) if next(5) == 0 else -1)
	var half := World.tile_polygon(
		0,
		{
			"collision_polygons": {"0": [0, 0, 0.5, 0, 0.5, 1, 0, 1]},
			"tile_size": [32, 32],
			"collision_disabled": []
		}
	)
	var layers := [
		layer("solid", 32, 60, 30, solid_cells, true, false),
		layer("water", 32, 60, 30, water_cells, false, true),
		layer("wide", 64, 30, 15, wide_cells, true, false)
	]
	# A half-cell polygon exercises the polygon path next to full rectangles.
	layers[0].polygons[2] = half
	layers[0].bounds[2] = World.polygon_bounds(half)
	layers[0].rectangles.erase(2)
	var cached := {"layers": layers, "terrain_chunks": {}}
	var plain := {"layers": layers}
	var same := true
	for probe in 3000:
		var left := (next(2100) - 60) * S + next(S)
		var top := (next(1050) - 60) * S + next(S)
		var right := left + next(80) * S
		var bottom := top + next(80) * S
		same = (
			same
			and (
				World.overlaps_box(cached, left, top, right, bottom)
				== World.overlaps_box(plain, left, top, right, bottom)
			)
			and (
				World.water_overlaps(cached, left, top, right, bottom)
				== World.water_overlaps(plain, left, top, right, bottom)
			)
			and (
				World.named_overlaps(cached, "wide", left, top, right, bottom)
				== World.named_overlaps(plain, "wide", left, top, right, bottom)
			)
		)
	check(same, "Terrain chunk cache equals reading every layer")
	var edge := [32 * S * 8, 32 * S * 8]
	check(
		(
			World.overlaps_box(cached, edge[0], edge[1], edge[0], edge[1])
			== World.overlaps_box(plain, edge[0], edge[1], edge[0], edge[1])
		),
		"Chunk corner probe"
	)


func layer(
	name: String,
	size: int,
	width: int,
	height: int,
	cells: PackedInt32Array,
	solid: bool,
	water: bool
) -> Dictionary:
	var bounds := {}
	var polygons := {}
	var rectangles := {}
	for cell: int in cells:
		if cell >= 0 and not bounds.has(cell):
			var points := PackedInt64Array([0, 0, size * S, 0, size * S, size * S, 0, size * S])
			polygons[cell] = points
			bounds[cell] = World.polygon_bounds(points)
			if World.axis_rectangle(points):
				rectangles[cell] = true
	return {
		"name": name,
		"layer": "layer1",
		"size": size,
		"width": width,
		"height": height,
		"cells": cells,
		"bounds": bounds,
		"polygons": polygons,
		"rectangles": rectangles,
		"solid": solid,
		"water": water
	}


func rectangle_checks() -> void:
	check(World.axis_rectangle(PackedInt64Array([0, 0, 9, 0, 9, 5, 0, 5])), "Rectangle")
	check(World.axis_rectangle(PackedInt64Array([9, 5, 0, 5, 0, 0, 9, 0])), "Reversed rectangle")
	check(not World.axis_rectangle(PackedInt64Array([0, 0, 9, 5, 9, 0, 0, 5])), "Bow tie")
	check(not World.axis_rectangle(PackedInt64Array([0, 0, 9, 0, 9, 5, 9, 0])), "Missing corner")
	check(not World.axis_rectangle(PackedInt64Array([0, 0, 9, 0, 0, 5])), "Triangle")
	check(not World.axis_rectangle(PackedInt64Array([0, 0, 9, 0, 9, 0, 0, 0])), "Flat")
	var same := true
	for trial in 4000:
		var x0 := next(40) - 20
		var y0 := next(40) - 20
		var x1 := x0 + 1 + next(30)
		var y1 := y0 + 1 + next(30)
		var points := PackedInt64Array([x0, y0, x1, y0, x1, y1, x0, y1])
		var left := next(80) - 40
		var top := next(80) - 40
		var right := left + next(30)
		var bottom := top + next(30)
		if left <= x1 and right >= x0 and top <= y1 and bottom >= y0:
			same = same and Polygon.overlaps_box(points, left, top, right, bottom)
	check(same, "A rectangle polygon overlaps whenever its inclusive bounds do")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
