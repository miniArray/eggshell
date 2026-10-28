extends RefCounted
## Terrain and registered solid movement for integer actor boxes.
## Supports: -1 terrain, 0 air, positive legacy bridge, <= -2 per-step solid.
## Per-step bindings are rebuilt before object motion, never saved as play facts.

const World = preload("res://src/sim/world.gd")
const EntityGrid = preload("res://src/sim/entity_grid.gd")
const Constants = preload("res://src/sim/script_constants.gd")
const S := preload("res://src/sim/units.gd").SCALE
const DEFAULT_JUMP := 776 * 60
const POUND_FALL := 2
## Solid index cell edge. Probes are actor-sized, so most touch one to four cells.
const CELL := 128 * S
## A probe covering more cells than this scans every row, as the unindexed path did.
const MAX_PROBE_CELLS := 64
const NO_CONTEXT := {}
## Tests and the identity proof set this to compare every indexed query with a full scan.
static var verify_index := false
static var verify_failures := 0
## Per type: which solid box hook it has (2 solid_boxes, 1 solid_box, 0 none).
static var _box_hooks := {}
## Box checks are assertions; release builds skip the loop that holds them.
static var _debug := OS.is_debug_build()


static func begin_step(state: Dictionary, world: Dictionary, registry: Script) -> void:
	var entities: Array = state.get("entities", [])
	var previous: Dictionary = world.get("solids_step", {})
	# A table changes only by replacement or by appending, so the same array with the same
	# size holds the same solid rows as last step. Verify runs check that with a scan.
	var same_table: bool = (
		not previous.is_empty()
		and is_same(previous.state, state)
		and previous.registry == registry
		and is_same(previous.entities, entities)
		and previous.count == entities.size()
	)
	var solids := []
	if not same_table or verify_index:
		for entity: Dictionary in entities:
			var type: Script = registry.lookup(entity.code)
			var mode := _solid_mode(type)
			if mode in [1, 2]:
				solids.append([entity, type, mode])
	if same_table and verify_index and not _same_rows(previous, state, registry, solids):
		verify_failures += 1
		push_error("Solid rows changed in a table that kept its identity and size")
	# The same table keeps its index: rows were refiled after every dispatch last step.
	var reuse := same_table or _same_rows(previous, state, registry, solids)
	var context := {
		"state": state,
		"registry": registry,
		"entities": entities,
		"count": entities.size(),
		"frame": int(state.get("frame", 0)),
		"rows": previous.rows if reuse else [],
		"shapes": [],
		"carried": false,
		"bumps": {},
		"grid": previous.grid if reuse else {},
		"by_token": previous.by_token if reuse else {},
		"dispatching": []
	}
	var rows: Array = context.rows
	if reuse:
		for row: Dictionary in rows:
			var entity: Dictionary = row.entity
			# Types build their box arrays fresh and nothing writes into them, so the old
			# boxes can share the arrays.
			var boxes := _boxes(row.type, entity)
			var moved: bool = row.x != entity.x or row.y != entity.y or row.status != entity.status
			row.x = entity.x
			row.y = entity.y
			row.status = entity.status
			row.old_boxes = boxes
			row.handles = []
			if moved or not _inside(row.region, boxes):
				_place(context, row, boxes)
		solids = []
	for index in solids.size():
		var entity: Dictionary = solids[index][0]
		var boxes := _boxes(solids[index][1], entity)
		var fresh := {
			"index": index,
			"entity": entity,
			"type": solids[index][1],
			"mode": solids[index][2],
			"x": entity.x,
			"y": entity.y,
			"status": entity.status,
			"old_boxes": boxes,
			"handles": [],
			"cells": [],
			"region": [],
			"bounded": solids[index][1].has_method("bounds")
		}
		rows.append(fresh)
		context.by_token[entity.get("token", -1 - index)] = fresh
		_place(context, fresh, boxes)
	if reuse and state.get("modal_token", 0):
		# The modal holder stepped before this call, outside registry dispatch tracking.
		var holder: Variant = context.by_token.get(state.modal_token)
		if holder != null:
			_place(context, holder, _boxes(holder.type, holder.entity))
	world.solids_step = context


static func _same_rows(
	previous: Dictionary, state: Dictionary, registry: Script, solids: Array
) -> bool:
	if (
		previous.is_empty()
		or not is_same(previous.state, state)
		or previous.registry != registry
		or previous.rows.size() != solids.size()
	):
		return false
	for index in solids.size():
		if not is_same(previous.rows[index].entity, solids[index][0]):
			return false
	return true


static func _inside(region: Array, boxes: Array) -> bool:
	if region.is_empty():
		return boxes.is_empty()
	for box: Array in boxes:
		if box[0] < region[0] or box[1] < region[1] or box[2] > region[2] or box[3] > region[3]:
			return false
	return true


static func _solid_mode(type: Script) -> int:
	return int(Constants.read(type, "SOLID", 0))


## Solid index. Each row is filed under the cells of its region: the union of its live
## boxes and its bounds around its position. A row is refiled at begin_step, after every
## registry dispatch on its entity and after a bump callback on it. While a dispatch on a
## row's entity runs, that row is always a candidate, so a solid that moves itself is seen
## by nested queries. Between dispatches, other code may only shrink or remove a solid's
## boxes (hits, removal) or enable boxes inside its bounds (switch toggles, which the
## registry also refiles). Code that moves or enlarges another entity's solid boxes must
## call refresh(). Every query evaluates candidate boxes live, so results, their order and
## side effects equal a scan of every row.
## It also marks the entity for the entity grid behind Registry.nearby, so code that moves
## another entity or changes a field its bounds read calls it too.
static func refresh(world: Dictionary, entity: Dictionary) -> void:
	EntityGrid.touch(world, entity)
	var context := _context(world)
	if context.is_empty():
		return
	var row: Variant = context.by_token.get(entity.get("token", 0))
	if row != null and is_same(row.entity, entity):
		_place(context, row, _boxes(row.type, entity))


## The token-to-row map of this step's solids, for registry dispatch bookkeeping.
static func solid_rows(world: Dictionary) -> Dictionary:
	var context := _context(world)
	return context.by_token if not context.is_empty() else {}


static func dispatch_begin(world: Dictionary, row: Dictionary) -> void:
	var context := _context(world)
	if not context.is_empty():
		context.dispatching.append(row.index)


static func dispatch_end(world: Dictionary, row: Dictionary) -> void:
	var context := _context(world)
	if not context.is_empty():
		context.dispatching.pop_back()
		_place(context, row, _boxes(row.type, row.entity))


static func _place(context: Dictionary, row: Dictionary, boxes: Array) -> void:
	var entity: Dictionary = row.entity
	var left := 0
	var top := 0
	var right := -1
	var bottom := -1
	var empty := true
	if row.bounded:
		var b: Array = row.type.bounds(entity)
		left = entity.x + mini(b[0], b[2])
		top = entity.y + mini(b[1], b[3])
		right = entity.x + maxi(b[0], b[2])
		bottom = entity.y + maxi(b[1], b[3])
		empty = false
	for box: Array in boxes:
		if empty:
			left = box[0]
			top = box[1]
			right = box[2]
			bottom = box[3]
			empty = false
		else:
			left = mini(left, box[0])
			top = mini(top, box[1])
			right = maxi(right, box[2])
			bottom = maxi(bottom, box[3])
	if empty:
		row.region = []
		if row.cells.is_empty():
			return
	row.region = [left, top, right, bottom]
	# World.floor_div() inlined: rows are refiled after every dispatch on a solid.
	var c0: int = left / CELL if left >= 0 else -((-left + CELL - 1) / CELL)
	var c1: int = top / CELL if top >= 0 else -((-top + CELL - 1) / CELL)
	var c2: int = right / CELL if right >= 0 else -((-right + CELL - 1) / CELL)
	var c3: int = bottom / CELL if bottom >= 0 else -((-bottom + CELL - 1) / CELL)
	var filed: Array = row.cells
	if (
		not empty
		and not filed.is_empty()
		and filed[0] == c0
		and filed[1] == c1
		and filed[2] == c2
		and filed[3] == c3
	):
		return
	var cells: Array = [] if empty else [c0, c1, c2, c3]
	var grid: Dictionary = context.grid
	if not row.cells.is_empty():
		for cy in range(row.cells[1], row.cells[3] + 1):
			for cx in range(row.cells[0], row.cells[2] + 1):
				var bucket: Array = grid[_cell_key(cx, cy)]
				bucket.erase(row.index)
	row.cells = cells
	if not cells.is_empty():
		for cy in range(cells[1], cells[3] + 1):
			for cx in range(cells[0], cells[2] + 1):
				var key := _cell_key(cx, cy)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(row.index)


static func _cell_key(cx: int, cy: int) -> int:
	return (cx << 32) ^ (cy & 0xffffffff)


## Row indices that may have a box touching the inclusive probe, in row order.
static func _candidates(context: Dictionary, left: int, top: int, right: int, bottom: int) -> Array:
	var cx0 := World.floor_div(left, CELL)
	var cy0 := World.floor_div(top, CELL)
	var cx1 := World.floor_div(right, CELL)
	var cy1 := World.floor_div(bottom, CELL)
	if (cx1 - cx0 + 1) * (cy1 - cy0 + 1) > MAX_PROBE_CELLS or right < left or bottom < top:
		return range(context.rows.size())
	if cx0 == cx1 and cy0 == cy1 and context.dispatching.is_empty():
		# One cell: its bucket holds each row once, so sorting a copy is the whole answer.
		var only: Variant = context.grid.get(_cell_key(cx0, cy0))
		if only == null:
			return []
		var sorted: Array = only.duplicate()
		sorted.sort()
		return sorted
	var found := {}
	var grid: Dictionary = context.grid
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var bucket: Variant = grid.get(_cell_key(cx, cy))
			if bucket != null:
				for index: int in bucket:
					found[index] = true
	for index: int in context.dispatching:
		found[index] = true
	var result := found.keys()
	result.sort()
	return result


static func registry_for(world: Dictionary) -> Script:
	return _context(world).get("registry")


static func overlaps(
	body: Dictionary, world: Dictionary, bounds: Array, dx: int = 0, dy: int = 0, bridge: int = 0
) -> bool:
	if World.overlaps_box(
		world,
		body.x + bounds[0] + dx,
		body.y + bounds[1] + dy,
		body.x + bounds[2] + dx,
		body.y + bounds[3] + dy
	):
		return true
	for shape: Dictionary in _shapes(
		world,
		body.x + bounds[0] + dx,
		body.y + bounds[1] + dy,
		body.x + bounds[2] + dx,
		body.y + bounds[3] + dy
	):
		if (
			shape.mode == 1
			and not is_same(body, shape.row.entity)
			and _shape_overlap(body, bounds, shape, dx, dy)
		):
			return true
	if bridge > 0:
		return bridge_overlap(body, world.bridges[bridge - 1], bounds, dx, dy)
	if bridge <= -2:
		var selected := _selected(world, bridge)
		return (
			not selected.is_empty()
			and not is_same(body, selected.row.entity)
			and _shape_overlap(body, bounds, selected, dx, dy)
		)
	return false


static func bridge_overlap(
	body: Dictionary, bridge: Dictionary, bounds: Array, dx: int = 0, dy: int = 0
) -> bool:
	return (
		body.x + bounds[2] + dx >= bridge.left
		and body.x + bounds[0] + dx <= bridge.right
		and body.y + bounds[3] + dy >= bridge.top
		and body.y + bounds[1] + dy <= bridge.top + 2 * S
	)


static func bridges_at(body: Dictionary, world: Dictionary, bounds: Array) -> Array[int]:
	var found: Array[int] = []
	for index in world.bridges.size():
		if bridge_overlap(body, world.bridges[index], bounds):
			found.append(index + 1)
	for shape: Dictionary in _shapes(
		world, body.x + bounds[0], body.y + bounds[1], body.x + bounds[2], body.y + bounds[3]
	):
		if (
			shape.mode == 2
			and not is_same(body, shape.row.entity)
			and _shape_overlap(body, bounds, shape)
		):
			found.append(shape.handle)
	return found


static func floor_at(body: Dictionary, world: Dictionary, bounds: Array) -> int:
	# A nearby wall is not a floor if the actor already overlaps it.
	if overlaps(body, world, bounds):
		return 0
	if World.overlaps_box(
		world,
		body.x + bounds[0],
		body.y + bounds[1] + S,
		body.x + bounds[2],
		body.y + bounds[3] + S
	):
		return -1
	var below := _shapes(
		world,
		body.x + bounds[0],
		body.y + bounds[1] + S,
		body.x + bounds[2],
		body.y + bounds[3] + S
	)
	for shape: Dictionary in below:
		if (
			shape.mode == 1
			and not is_same(body, shape.row.entity)
			and _shape_overlap(body, bounds, shape, 0, S)
		):
			return shape.handle
	for index in world.bridges.size():
		var bridge: Dictionary = world.bridges[index]
		if body.y + bounds[3] <= bridge.top and bridge_overlap(body, bridge, bounds, 0, S):
			return index + 1
	for shape: Dictionary in below:
		if (
			shape.mode == 2
			and not is_same(body, shape.row.entity)
			and body.y + bounds[3] <= shape.box[1]
			and _shape_overlap(body, bounds, shape, 0, S)
		):
			return shape.handle
	return 0


static func track_floor(body: Dictionary, world: Dictionary, bounds: Array) -> int:
	var support := floor_at(body, world, bounds)
	var top: int = world.bridges[support - 1].top if support > 0 else 0
	if support <= -2:
		top = _selected(world, support).box[1]
	if _one_way(world, support) and body.y + bounds[3] == top:
		# Exact top contact can occur at spawn or restoration.
		push_out(body, world, bounds, 0, -1, 2 * S, support)
	if support != 0 and body.vy > 0:
		refine(body, world, bounds, 0, -1, support if _one_way(world, support) else 0)
		body.vy = 0
	return support


static func by_wall(body: Dictionary, world: Dictionary, bounds: Array, direction: int) -> bool:
	return (
		overlaps(body, world, bounds, direction * S, 0)
		and overlaps(body, world, bounds, direction * S, -S)
	)


static func prepare(body: Dictionary, world: Dictionary, bounds: Array) -> bool:
	_carry(body, world, bounds)
	if not overlaps(body, world, bounds):
		return true
	# Without solid rows near the body, the search below only reads static terrain, so its
	# outcome for this position and box is remembered per map. Bodies held inside terrain
	# repeat the same search every step.
	var memo: Variant = world.get("terrain_escapes")
	var key: Array = []
	if memo != null and _no_solids_near(world, body, bounds):
		key = [body.x, body.y, bounds[0], bounds[1], bounds[2], bounds[3]]
		var known: Variant = memo.get(key)
		if known != null:
			body.x = known[1]
			body.y = known[2]
			if known[0] == 2:
				body.vy = 0
			return known[0] != 0
	var outcome := _escape(body, world, bounds)
	if not key.is_empty():
		if memo.size() >= World.MAX_TERRAIN_HITS:
			memo.clear()
		memo[key] = [outcome, body.x, body.y]
	if outcome == 2:
		body.vy = 0
	return outcome != 0


## The push-out search of prepare(): 0 when no free place was found (the body is back at
## its start), 1 when it moved to one, 2 when it moved up and its vertical speed stops.
static func _escape(body: Dictionary, world: Dictionary, bounds: Array) -> int:
	var width: int = bounds[2] - bounds[0]
	var height: int = bounds[3] - bounds[1]
	if push_out(body, world, bounds, 0, -1, height / 8):
		return 2
	if push_axis(body, world, bounds, true, width / 2):
		return 1
	if push_axis(body, world, bounds, false, height / 2):
		return 1
	return 1 if push_nearest(body, world, bounds, maxi(width, height) / 2) else 0


## Whether no solid row can take part in _escape(): none filed near any position it
## probes (the body box grown by its largest push distance plus refinement), and none
## dispatching. Then every probe there reads terrain only.
static func _no_solids_near(world: Dictionary, body: Dictionary, bounds: Array) -> bool:
	var context := _context(world)
	if context.is_empty():
		return true
	var reach: int = maxi(bounds[2] - bounds[0], bounds[3] - bounds[1]) + 4 * S
	return (
		_candidates(
			context,
			body.x + bounds[0] - reach,
			body.y + bounds[1] - reach,
			body.x + bounds[2] + reach,
			body.y + bounds[3] + reach
		)
		. is_empty()
	)


static func horizontal(
	body: Dictionary,
	world: Dictionary,
	bounds: Array,
	distance: int,
	support: int,
	jumping: bool = false,
	jump_speed: int = DEFAULT_JUMP
) -> int:
	if distance == 0:
		return 0
	var start_x: int = body.x
	var start_y: int = body.y
	var direction := 1 if distance > 0 else -1
	var old_bridges := bridges_at(body, world, bounds)
	# A one-pixel side probe raised one pixel separates a ramp from a wall.
	var wall := overlaps(body, world, bounds, direction * S, -S)
	body.x += distance
	var obstacle := overlaps(body, world, bounds)
	var bridge := 0
	if not obstacle and _one_way(world, support):
		for index in bridges_at(body, world, bounds):
			if index not in old_bridges:
				bridge = index
				break
	if obstacle:
		_bump(body, world, bounds, 2 if direction > 0 else 3)
		obstacle = overlaps(body, world, bounds)
	if obstacle or bridge:
		var climb := absi(distance) + 2 * S
		if not wall and push_out(body, world, bounds, 0, -1, climb, bridge):
			if not jumping and absi(body.vy) < absi(jump_speed / 4):
				body.vy = 0
		else:
			var retreat := maxi(absi(distance) * 5 / 2, bounds[2] - bounds[0])
			if push_out(body, world, bounds, -direction, 0, retreat):
				if support < 0 and not _one_way(world, support) and bridge == 0:
					var saved_y: int = body.y
					body.y += S
					if (
						not overlaps(body, world, bounds)
						or not push_out(body, world, bounds, 0, -1, 3 * S)
					):
						body.y = saved_y
			else:
				body.x = start_x
				body.y = start_y
			if bridge == 0:
				body.vx = 0
	else:
		var floor := floor_at(body, world, bounds)
		if support != 0 and floor == 0:
			# Follow a descending ramp, but do not stick to a distant lower floor.
			var drop := ((absi(distance) + S - 1) / S + 2) * S
			var saved_y: int = body.y
			body.y += drop
			var snapped := false
			for index in bridges_at(body, world, bounds):
				if (
					index not in old_bridges
					and push_out(body, world, bounds, 0, -1, drop + 2 * S, index)
				):
					snapped = true
					break
			if not snapped:
				if (
					not overlaps(body, world, bounds)
					or not push_out(body, world, bounds, 0, -1, drop + 2 * S)
				):
					body.y = saved_y
		elif floor != 0 and body.vy == 0:
			refine(body, world, bounds, 0, -1, floor if _one_way(world, floor) else 0)
	if body.vx != 0 and by_wall(body, world, bounds, 1 if body.vx > 0 else -1):
		body.vx = 0
	return body.x - start_x


static func vertical(
	body: Dictionary, world: Dictionary, bounds: Array, distance: int, support: int = 0
) -> int:
	if distance == 0:
		return 0
	var start_y: int = body.y
	var old_bridges := bridges_at(body, world, bounds)
	body.y += distance
	var obstacle := overlaps(body, world, bounds)
	var bridge := 0
	if not obstacle and distance > 0 and support == 0:
		for index in bridges_at(body, world, bounds):
			if index not in old_bridges:
				bridge = index
				break
	if distance < 0:
		_bump(body, world, bounds, 0, 0, start_y + bounds[1])
	elif body.get("move_action", 0) == POUND_FALL:
		_bump(body, world, bounds, 1, bridge, start_y + bounds[3])
	obstacle = overlaps(body, world, bounds)
	if bridge and _selected(world, bridge).is_empty() and bridge < 0:
		bridge = 0
	if obstacle or bridge:
		var limit := maxi(absi(distance) * (20 if bridge else 11) / 10, 2 * S)
		if not push_out(body, world, bounds, 0, 1 if distance < 0 else -1, limit, bridge):
			body.y = start_y
		body.vy = 0
	return body.y - start_y


## This step's solid context, or a shared read-only empty one (callers only read it).
static func _context(world: Dictionary) -> Dictionary:
	var context: Variant = world.get("solids_step")
	if context == null or context.is_empty() or context.frame != context.state.get("frame", 0):
		return NO_CONTEXT
	return context


static func _boxes(type: Script, entity: Dictionary) -> Array:
	var boxes: Array = []
	var kind: Variant = _box_hooks.get(type)
	if kind == null:
		kind = 2 if type.has_method("solid_boxes") else (1 if type.has_method("solid_box") else 0)
		_box_hooks[type] = kind
	if kind == 2:
		boxes = type.solid_boxes(entity)
	elif kind == 1:
		var box: Array = type.solid_box(entity)
		if not box.is_empty():
			boxes = [box]
	if not _debug:
		return boxes
	for box: Array in boxes:
		assert(box.size() == 4 and box[0] < box[2] and box[1] < box[3], "Invalid solid box")
		for value: Variant in box:
			assert(value is int, "Solid coordinates must be integers")
	return boxes


## Live shapes of the rows that may touch the inclusive probe, in row then part order.
## Shapes outside the probe can appear; every caller tests overlap with this probe.
static func _shapes(world: Dictionary, left: int, top: int, right: int, bottom: int) -> Array:
	var context := _context(world)
	var result := []
	if context.is_empty():
		return result
	var rows: Array = context.rows
	for index: int in _candidates(context, left, top, right, bottom):
		var row: Dictionary = rows[index]
		if row.entity.status != 1:
			continue
		var boxes := _boxes(row.type, row.entity)
		for part in boxes.size():
			# Handles are transient, unique per row part, and only compared for identity.
			while row.handles.size() <= part:
				row.handles.append(-2 - context.shapes.size())
				context.shapes.append({"row": row, "part": row.handles.size() - 1})
			result.append(
				{"handle": row.handles[part], "mode": row.mode, "box": boxes[part], "row": row}
			)
	if verify_index:
		_verify(context, result, [left, top, right, bottom])
	return result


## Compares the indexed shapes touching a probe with a scan of every row.
static func _verify(context: Dictionary, result: Array, probe: Array) -> void:
	var expected := []
	for row: Dictionary in context.rows:
		if row.entity.status != 1:
			continue
		var boxes := _boxes(row.type, row.entity)
		for part in boxes.size():
			if _touches(boxes[part], probe):
				expected.append([row.index, part, boxes[part]])
	var actual := []
	for shape: Dictionary in result:
		if _touches(shape.box, probe):
			actual.append([shape.row.index, shape.row.handles.find(shape.handle), shape.box])
	if actual != expected:
		verify_failures += 1
		push_error("Solid index differs from a full scan at %s" % [probe])


static func _touches(box: Array, probe: Array) -> bool:
	return box[2] >= probe[0] and box[0] <= probe[2] and box[3] >= probe[1] and box[1] <= probe[3]


static func _selected(world: Dictionary, handle: int) -> Dictionary:
	var context := _context(world)
	if handle > -2 or context.is_empty() or -2 - handle >= context.shapes.size():
		return {}
	var reference: Dictionary = context.shapes[-2 - handle]
	var row: Dictionary = reference.row
	if row.entity.status != 1:
		return {}
	var boxes := _boxes(row.type, row.entity)
	if reference.part >= boxes.size():
		return {}
	return {"handle": handle, "mode": row.mode, "box": boxes[reference.part], "row": row}


static func _one_way(world: Dictionary, support: int) -> bool:
	if support > 0:
		return true
	var shape := _selected(world, support)
	return not shape.is_empty() and shape.mode == 2


static func _shape_overlap(
	body: Dictionary, bounds: Array, shape: Dictionary, dx := 0, dy := 0
) -> bool:
	if not _box_overlap(body, bounds, shape.box, dx, dy):
		return false
	var row: Dictionary = shape.row
	if not row.type.has_method("solid_touches"):
		return true
	return row.type.solid_touches(
		row.entity,
		[
			body.x + bounds[0] + dx,
			body.y + bounds[1] + dy,
			body.x + bounds[2] + dx,
			body.y + bounds[3] + dy
		]
	)


static func _box_overlap(body: Dictionary, bounds: Array, box: Array, dx := 0, dy := 0) -> bool:
	return (
		body.x + bounds[2] + dx >= box[0]
		and body.x + bounds[0] + dx <= box[2]
		and body.y + bounds[3] + dy >= box[1]
		and body.y + bounds[1] + dy <= box[3]
	)


static func _carry(body: Dictionary, world: Dictionary, bounds: Array) -> void:
	var context := _context(world)
	if context.is_empty() or not is_same(body, context.state) or context.carried:
		return
	context.carried = true
	if body.vy != 0 or not body.get("on_floor", 0):
		return
	for row: Dictionary in context.rows:
		# The cheap old-box test runs first; every condition must hold, so order is free.
		var supported := false
		for box: Array in row.old_boxes:
			if body.y + bounds[3] <= box[1] and _box_overlap(body, bounds, box, 0, S):
				supported = true
				break
		if (
			not supported
			or row.status != 1
			or row.entity.status != 1
			or _boxes(row.type, row.entity).is_empty()
		):
			continue
		var dx: int = row.entity.x - row.x
		var dy: int = row.entity.y - row.y
		body.x += dx
		body.y += dy
		if overlaps(body, world, bounds) and (dx or dy):
			_carry_retreat(body, world, bounds, dx, dy)
		return


static func _carry_retreat(
	body: Dictionary, world: Dictionary, bounds: Array, dx: int, dy: int
) -> void:
	var length := _root(dx * dx + dy * dy)
	var start_x: int = body.x
	var start_y: int = body.y
	var last_blocked := 0
	for distance in range(0, length * 5 / 2, S):
		body.x = start_x - dx * distance / length
		body.y = start_y - dy * distance / length
		if not overlaps(body, world, bounds):
			var safe := distance
			var blocked := false
			var position := distance
			for divisor in [2, 4, 8, 16]:
				position += S / divisor * (1 if blocked else -1)
				position = maxi(last_blocked, position)
				body.x = start_x - dx * position / length
				body.y = start_y - dy * position / length
				blocked = overlaps(body, world, bounds)
				if not blocked:
					safe = position
			body.x = start_x - dx * safe / length
			body.y = start_y - dy * safe / length
			return
		last_blocked = distance
	body.x = start_x
	body.y = start_y


static func _root(value: int) -> int:
	var low := 0
	var high := mini(value, 3037000499)
	while low < high:
		var middle := (low + high + 1) / 2
		if middle <= value / middle:
			low = middle
		else:
			high = middle - 1
	return low


static func _bump(
	body: Dictionary, world: Dictionary, bounds: Array, side: int, one_way := 0, previous_edge := 0
) -> void:
	var context := _context(world)
	if context.is_empty() or not is_same(body, context.state):
		return
	var targets := []
	for shape: Dictionary in _shapes(
		world, body.x + bounds[0], body.y + bounds[1], body.x + bounds[2], body.y + bounds[3]
	):
		if shape.mode == 2 and shape.handle != one_way:
			continue
		if side == 0 and previous_edge < shape.box[3] or side == 1 and previous_edge > shape.box[1]:
			continue
		var row: Dictionary = shape.row
		if _shape_overlap(body, bounds, shape) and row.type.has_method("bump"):
			targets.append(row)
	# Fix the contact set before a callback can move the player or another solid.
	for row: Dictionary in targets:
		var key := "%s:%d" % [row.entity.id, side]
		if context.bumps.has(key) or row.entity.status != 1:
			continue
		context.bumps[key] = true
		var grid: Variant = EntityGrid.current(world)
		dispatch_begin(world, row)
		EntityGrid.begin(grid, row.entity)
		row.type.bump(row.entity, context.state, world, side)
		EntityGrid.end(grid, row.entity)
		dispatch_end(world, row)


static func support_in_box(
	world: Dictionary, left: int, top: int, right: int, bottom: int, ignore: Dictionary = {}
) -> bool:
	if World.overlaps_box(world, left, top, right, bottom):
		return true
	for bridge: Dictionary in world.bridges:
		if (
			top <= bridge.top
			and bottom >= bridge.top
			and right >= bridge.left
			and left <= bridge.right
		):
			return true
	var probe := {"x": 0, "y": 0}
	var bounds := [left, top, right, bottom]
	for shape: Dictionary in _shapes(world, left, top, right, bottom):
		if is_same(ignore, shape.row.entity):
			continue
		if shape.mode == 2 and top > shape.box[1]:
			continue
		if _shape_overlap(probe, bounds, shape):
			return true
	return false


static func strike_above(
	entity: Dictionary, state: Dictionary, world: Dictionary, box: Array, kind: int
) -> void:
	var registry := registry_for(world)
	if registry == null:
		return
	for target: Dictionary in state.entities:
		if is_same(entity, target) or target.status != 1:
			continue
		var type: Script = registry.lookup(target.code)
		if not type.has_method("hit") or not type.has_method("bounds"):
			continue
		var bounds: Array = type.bounds(target)
		var foot: int = target.y + bounds[3]
		if (
			target.x + bounds[2] >= box[0]
			and target.x + bounds[0] <= box[2]
			and foot <= box[1] + S
			and foot >= box[1] - 2 * S
		):
			type.hit(target, state, world, kind, entity.x)
			refresh(world, target)


static func push_out(
	body: Dictionary,
	world: Dictionary,
	bounds: Array,
	dx: int,
	dy: int,
	limit: int,
	bridge: int = 0
) -> bool:
	var start_x: int = body.x
	var start_y: int = body.y
	var touched := false
	for offset in range(0, limit, S):
		body.x = start_x + dx * offset
		body.y = start_y + dy * offset
		if not overlaps(body, world, bounds, 0, 0, bridge):
			if touched:
				refine(body, world, bounds, dx, dy, bridge)
			return true
		touched = true
	body.x = start_x
	body.y = start_y
	return false


static func refine(
	body: Dictionary, world: Dictionary, bounds: Array, dx: int, dy: int, bridge: int = 0
) -> void:
	var safe_x: int = body.x
	var safe_y: int = body.y
	var blocked := false
	# Four fractional probes retain the last free point, to 1/16 pixel.
	for divisor in [2, 4, 8, 16]:
		var offset: int = S / divisor * (1 if blocked else -1)
		body.x += dx * offset
		body.y += dy * offset
		blocked = overlaps(body, world, bounds, 0, 0, bridge)
		if not blocked:
			safe_x = body.x
			safe_y = body.y
	if blocked:
		body.x = safe_x
		body.y = safe_y


static func push_axis(
	body: Dictionary, world: Dictionary, bounds: Array, horizontal_axis: bool, limit: int
) -> bool:
	var start_x: int = body.x
	var start_y: int = body.y
	for offset in range(0, limit, S):
		for direction in [-1, 1]:
			var dx: int = direction if horizontal_axis else 0
			var dy: int = 0 if horizontal_axis else direction
			body.x = start_x + dx * offset
			body.y = start_y + dy * offset
			if not overlaps(body, world, bounds):
				refine(body, world, bounds, dx, dy)
				return true
	body.x = start_x
	body.y = start_y
	return false


static func push_nearest(body: Dictionary, world: Dictionary, bounds: Array, limit: int) -> bool:
	var start_x: int = body.x
	var start_y: int = body.y
	var directions := [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]]
	var offset := 0
	var index := 0
	while offset <= limit:
		if index == 0:
			offset += S
		var direction: Array = directions[index]
		body.x = World.floor_div(start_x, S) * S + direction[0] * offset
		body.y = World.floor_div(start_y, S) * S + direction[1] * offset
		if not overlaps(body, world, bounds):
			return true
		index = (index + 1) % directions.size()
	body.x = start_x
	body.y = start_y
	return false
