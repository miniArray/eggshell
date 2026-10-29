extends RefCounted
## Entity grid behind `Registry.nearby`. Each entity of the current table is filed under the
## 128 px cells of its region: its `bounds` around its position (both corners ordered), or
## its position when the type has no bounds. Queries test candidates live with the scan's
## test and return them in entity order, so results equal a scan of the table.
##
## The grid lives in `world.entity_grid` and is never saved. It is built at the first query
## on a table and kept while that play state steps:
## - Entities that leave the table (compaction) or join it (runtime creation) are found by a
##   walk of the table at the next query; a replaced table is filed again from scratch.
## - The registry marks an entity after every dispatch on it (lifecycle and step, contact,
##   tongue, request consumption, switch toggle, modal step) and collision after a bump
##   callback. Marked entities are refiled at the next query.
## - While a dispatch on an entity runs, that entity is always a candidate.
## - Code that moves another entity or changes a field its bounds read must call
##   `Collision.refresh(world, entity)`, which marks it too. Hits from one entity on
##   another are such changes.

const S := preload("res://src/sim/units.gd").SCALE
## Cell edge. Area probes are body-sized, so most touch one to four cells.
const CELL := 128 * S
## A probe covering more cells than this is answered by a scan of the table.
const MAX_PROBE_CELLS := 64
## A region covering more cells than this is kept in a list every query reads.
const MAX_ROW_CELLS := 256
## Row layout: [entity, order, left cell, top cell, right cell, bottom cell, refile pass].
const ENTITY := 0
const ORDER := 1
const UNFILED := -(1 << 62)
## Per code: the type when it has bounds, false when entities are points.
static var _bounded := {}
## Keeping the grid costs about one refile per dispatched entity per step, and a scan costs
## about the same per query. The grid answers a step's queries only when the previous step
## asked at least this many; otherwise queries scan. Both give the same answers. Tests set
## it to 0 to use the grid from the first query.
static var min_queries := 4


## The grid of this play state, created unbuilt when the state changes. The registry calls
## it at the start of each step; `dispatching` and `dirty` keep their identity for its loops.
static func attach(state: Dictionary, world: Dictionary) -> Dictionary:
	var grid: Variant = world.get("entity_grid")
	if grid == null or not is_same(grid.state, state):
		grid = {
			"state": state,
			"built": false,
			"usable": true,
			"entities": null,
			"count": 0,
			"rows": [],
			"by_token": {},
			"by_order": {},
			"cells": {},
			"wide": {},
			"dirty": [],
			"dispatching": [],
			"next_order": 0,
			"pass": 0,
			"queries": 0,
			"use": min_queries <= 0,
		}
		world.entity_grid = grid
		return grid
	grid.use = grid.queries >= min_queries
	grid.queries = 0
	if not grid.use or not grid.built or grid.dirty.size() > grid.count + 64:
		# Unused this step, or marks piled up: filing again costs less than replaying them.
		grid.built = false
		grid.dirty.clear()
	return grid


## The attached grid, or null.
static func current(world: Dictionary) -> Variant:
	return world.get("entity_grid")


## Marks an entity that other code moved or changed, so the next query refiles it.
static func touch(world: Dictionary, entity: Dictionary) -> void:
	var grid: Variant = world.get("entity_grid")
	if grid != null and grid.built:
		grid.dirty.append(entity)


## Dispatch bookkeeping for callers outside the registry loops (bump callbacks).
static func begin(grid: Variant, entity: Dictionary) -> void:
	if grid != null:
		grid.dispatching.append(entity)


static func end(grid: Variant, entity: Dictionary) -> void:
	if grid != null:
		grid.dispatching.pop_back()
		grid.dirty.append(entity)


## Entities whose bounds may overlap `box`, in entity order, equal to Registry's scan.
## Returns null when the grid cannot answer; the caller then scans the table.
static func query(
	state: Dictionary, world: Dictionary, box: Array, types: Dictionary, fallback: Script
) -> Variant:
	var grid: Variant = world.get("entity_grid")
	if grid == null or not is_same(grid.state, state):
		return null
	grid.queries += 1
	if not grid.use:
		return null
	var left: int = box[0]
	var top: int = box[1]
	var right: int = box[2]
	var bottom: int = box[3]
	if right < left or bottom < top:
		return null
	var cx0 := _cell(left)
	var cy0 := _cell(top)
	var cx1 := _cell(right)
	var cy1 := _cell(bottom)
	if (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > MAX_PROBE_CELLS:
		return null
	_sync(grid, state.entities, types, fallback)
	if not grid.usable:
		return null
	var found := {}
	var cells: Dictionary = grid.cells
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var bucket: Variant = cells.get((cx << 32) ^ (cy & 0xffffffff))
			if bucket != null:
				for order: int in bucket:
					found[order] = true
	for order: int in grid.wide:
		found[order] = true
	var by_token: Dictionary = grid.by_token
	for entity: Dictionary in grid.dispatching:
		var row: Variant = by_token.get(entity.get("token"))
		if row != null and is_same(row[ENTITY], entity):
			found[row[ORDER]] = true
	var orders := found.keys()
	orders.sort()
	var result := []
	var by_order: Dictionary = grid.by_order
	for order: int in orders:
		var entity: Dictionary = by_order[order][ENTITY]
		var type: Variant = _bounded.get(entity.code)
		if type == null:
			type = _bounds_type(entity.code, types, fallback)
		if _touches(entity, type, left, top, right, bottom):
			result.append(entity)
	return result


## The reference answer: every entity of the table whose region touches `box`, in order.
static func scan(entities: Array, box: Array, types: Dictionary, fallback: Script) -> Array:
	var result := []
	var left: int = box[0]
	var top: int = box[1]
	var right: int = box[2]
	var bottom: int = box[3]
	for entity: Dictionary in entities:
		var type: Variant = _bounded.get(entity.code)
		if type == null:
			type = _bounds_type(entity.code, types, fallback)
		if _touches(entity, type, left, top, right, bottom):
			result.append(entity)
	return result


## Whether two answers hold the same entities in the same order.
static func same(found: Array, expected: Array) -> bool:
	if found.size() != expected.size():
		return false
	for index in found.size():
		if not is_same(found[index], expected[index]):
			return false
	return true


## The test behind every answer: the entity's bounds around its position touch the
## inclusive box (edges count); an entity without bounds is its position. `type` is the
## code's type, or false when it has no bounds.
static func _touches(
	entity: Dictionary, type: Variant, left: int, top: int, right: int, bottom: int
) -> bool:
	var x: int = entity.x
	var y: int = entity.y
	if type is bool:
		return x >= left and x <= right and y >= top and y <= bottom
	var bounds: Array = type.bounds(entity)
	return (
		x + bounds[2] >= left
		and x + bounds[0] <= right
		and y + bounds[3] >= top
		and y + bounds[1] <= bottom
	)


static func _bounds_type(code: String, types: Dictionary, fallback: Script) -> Variant:
	var type: Script = types.get(code, fallback)
	var result: Variant = type if type.has_method("bounds") else false
	_bounded[code] = result
	return result


static func _cell(value: int) -> int:
	return value / CELL if value >= 0 else -((-value + CELL - 1) / CELL)


## Brings the grid up to date with the table: build, then table changes, then marks.
static func _sync(grid: Dictionary, entities: Array, types: Dictionary, fallback: Script) -> void:
	if not grid.built:
		_build(grid, entities, types, fallback)
		return
	if not is_same(grid.entities, entities) or grid.count != entities.size():
		_reconcile(grid, entities, types, fallback)
	var dirty: Array = grid.dirty
	if dirty.is_empty():
		return
	grid.pass += 1
	var refile_pass: int = grid.pass
	var by_token: Dictionary = grid.by_token
	for entity: Dictionary in dirty:
		var row: Variant = by_token.get(entity.get("token"))
		if row != null and row[6] != refile_pass and is_same(row[ENTITY], entity):
			row[6] = refile_pass
			_file(grid, row, types, fallback)
	dirty.clear()


static func _build(grid: Dictionary, entities: Array, types: Dictionary, fallback: Script) -> void:
	grid.rows = []
	grid.by_token = {}
	grid.by_order = {}
	grid.cells = {}
	grid.wide = {}
	grid.dirty.clear()
	grid.usable = true
	grid.next_order = 0
	for entity: Dictionary in entities:
		_add(grid, entity, types, fallback)
	grid.entities = entities
	grid.count = entities.size()
	grid.built = true


## Walks the table against the filed rows. Rows whose entity left are removed; entities not
## yet filed get new rows. Orders stay increasing along the table because every new row is
## numbered after all earlier ones.
static func _reconcile(
	grid: Dictionary, entities: Array, types: Dictionary, fallback: Script
) -> void:
	var rows: Array = grid.rows
	var kept := []
	var index := 0
	grid.rows = kept
	for entity: Dictionary in entities:
		while index < rows.size() and not is_same(rows[index][ENTITY], entity):
			_remove(grid, rows[index])
			index += 1
		if index < rows.size():
			kept.append(rows[index])
			index += 1
		else:
			_add(grid, entity, types, fallback)
	while index < rows.size():
		_remove(grid, rows[index])
		index += 1
	grid.entities = entities
	grid.count = entities.size()


static func _add(grid: Dictionary, entity: Dictionary, types: Dictionary, fallback: Script) -> void:
	var token: Variant = entity.get("token")
	if grid.by_token.has(token):
		# Tokens identify rows for dispatch marks; a repeated token makes them ambiguous.
		grid.usable = false
	var row := [entity, grid.next_order, UNFILED, 0, 0, 0, -1]
	grid.next_order += 1
	grid.rows.append(row)
	grid.by_token[token] = row
	grid.by_order[row[ORDER]] = row
	_file(grid, row, types, fallback)


static func _remove(grid: Dictionary, row: Array) -> void:
	_unfile(grid, row)
	grid.by_order.erase(row[ORDER])
	var token: Variant = row[ENTITY].get("token")
	if is_same(grid.by_token.get(token), row):
		grid.by_token.erase(token)


static func _file(grid: Dictionary, row: Array, types: Dictionary, fallback: Script) -> void:
	var entity: Dictionary = row[ENTITY]
	var x: int = entity.x
	var y: int = entity.y
	var type: Variant = _bounded.get(entity.code)
	if type == null:
		type = _bounds_type(entity.code, types, fallback)
	var left := x
	var top := y
	var right := x
	var bottom := y
	if not type is bool:
		var b: Array = type.bounds(entity)
		left += mini(b[0], b[2])
		top += mini(b[1], b[3])
		right += maxi(b[0], b[2])
		bottom += maxi(b[1], b[3])
	# _cell() inlined: refiles run once per dispatched entity per step.
	var c0: int = left / CELL if left >= 0 else -((-left + CELL - 1) / CELL)
	var c1: int = top / CELL if top >= 0 else -((-top + CELL - 1) / CELL)
	var c2: int = right / CELL if right >= 0 else -((-right + CELL - 1) / CELL)
	var c3: int = bottom / CELL if bottom >= 0 else -((-bottom + CELL - 1) / CELL)
	if c0 == row[2] and c1 == row[3] and c2 == row[4] and c3 == row[5]:
		return
	_unfile(grid, row)
	row[2] = c0
	row[3] = c1
	row[4] = c2
	row[5] = c3
	var order: int = row[ORDER]
	if (c2 - c0 + 1) * (c3 - c1 + 1) > MAX_ROW_CELLS:
		grid.wide[order] = true
		return
	var cells: Dictionary = grid.cells
	for cy in range(c1, c3 + 1):
		for cx in range(c0, c2 + 1):
			var key := (cx << 32) ^ (cy & 0xffffffff)
			var bucket: Variant = cells.get(key)
			if bucket == null:
				cells[key] = [order]
			else:
				bucket.append(order)


static func _unfile(grid: Dictionary, row: Array) -> void:
	if row[2] == UNFILED:
		return
	var order: int = row[ORDER]
	var c0: int = row[2]
	row[2] = UNFILED
	if grid.wide.has(order):
		grid.wide.erase(order)
		return
	var cells: Dictionary = grid.cells
	for cy in range(row[3], row[5] + 1):
		for cx in range(c0, row[4] + 1):
			var bucket: Array = cells[(cx << 32) ^ (cy & 0xffffffff)]
			bucket.erase(order)
