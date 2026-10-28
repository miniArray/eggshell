extends RefCounted
## Terrain and registered solid movement for integer actor boxes.
## Supports: -1 terrain, 0 air, positive legacy bridge, <= -2 per-step solid.
## Per-step bindings are rebuilt before object motion, never saved as play facts.

const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const DEFAULT_JUMP := 776 * 60
const POUND_FALL := 2


static func begin_step(state: Dictionary, world: Dictionary, registry: Script) -> void:
	var rows := []
	for entity: Dictionary in state.get("entities", []):
		var type: Script = registry.lookup(entity.code)
		var mode := int(type.get_script_constant_map().get("SOLID", 0))
		if mode not in [1, 2]:
			continue
		rows.append(
			{
				"entity": entity,
				"type": type,
				"mode": mode,
				"x": entity.x,
				"y": entity.y,
				"status": entity.status,
				"old_boxes": _boxes(type, entity).duplicate(true),
				"handles": []
			}
		)
	world.solids_step = {
		"state": state,
		"registry": registry,
		"frame": int(state.get("frame", 0)),
		"rows": rows,
		"shapes": [],
		"carried": false,
		"bumps": {}
	}


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
	for shape: Dictionary in _shapes(world):
		if (
			shape.mode == 1
			and not is_same(body, shape.row.entity)
			and _box_overlap(body, bounds, shape.box, dx, dy)
		):
			return true
	if bridge > 0:
		return bridge_overlap(body, world.bridges[bridge - 1], bounds, dx, dy)
	if bridge <= -2:
		var selected := _selected(world, bridge)
		return (
			not selected.is_empty()
			and not is_same(body, selected.row.entity)
			and _box_overlap(body, bounds, selected.box, dx, dy)
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
	for shape: Dictionary in _shapes(world):
		if (
			shape.mode == 2
			and not is_same(body, shape.row.entity)
			and _box_overlap(body, bounds, shape.box)
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
	for shape: Dictionary in _shapes(world):
		if (
			shape.mode == 1
			and not is_same(body, shape.row.entity)
			and _box_overlap(body, bounds, shape.box, 0, S)
		):
			return shape.handle
	for index in world.bridges.size():
		var bridge: Dictionary = world.bridges[index]
		if body.y + bounds[3] <= bridge.top and bridge_overlap(body, bridge, bounds, 0, S):
			return index + 1
	for shape: Dictionary in _shapes(world):
		if (
			shape.mode == 2
			and not is_same(body, shape.row.entity)
			and body.y + bounds[3] <= shape.box[1]
			and _box_overlap(body, bounds, shape.box, 0, S)
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
	var width: int = bounds[2] - bounds[0]
	var height: int = bounds[3] - bounds[1]
	if push_out(body, world, bounds, 0, -1, height / 8):
		body.vy = 0
		return true
	if push_axis(body, world, bounds, true, width / 2):
		return true
	if push_axis(body, world, bounds, false, height / 2):
		return true
	return push_nearest(body, world, bounds, maxi(width, height) / 2)


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
		_bump(body, world, bounds, 0)
	elif body.get("move_action", 0) == POUND_FALL:
		_bump(body, world, bounds, 1, bridge)
	obstacle = overlaps(body, world, bounds)
	if bridge and _selected(world, bridge).is_empty() and bridge < 0:
		bridge = 0
	if obstacle or bridge:
		var limit := maxi(absi(distance) * (20 if bridge else 11) / 10, 2 * S)
		if not push_out(body, world, bounds, 0, 1 if distance < 0 else -1, limit, bridge):
			body.y = start_y
		body.vy = 0
	return body.y - start_y


static func _context(world: Dictionary) -> Dictionary:
	var context: Dictionary = world.get("solids_step", {})
	if context.is_empty() or context.frame != context.state.get("frame", 0):
		return {}
	return context


static func _boxes(type: Script, entity: Dictionary) -> Array:
	var boxes: Array = []
	if type.has_method("solid_boxes"):
		boxes = type.solid_boxes(entity)
	elif type.has_method("solid_box"):
		var box: Array = type.solid_box(entity)
		if not box.is_empty():
			boxes = [box]
	for box: Array in boxes:
		assert(box.size() == 4 and box[0] < box[2] and box[1] < box[3], "Invalid solid box")
		for value: Variant in box:
			assert(value is int, "Solid coordinates must be integers")
	return boxes


static func _shapes(world: Dictionary) -> Array:
	var context := _context(world)
	var result := []
	if context.is_empty():
		return result
	for row: Dictionary in context.rows:
		if row.entity.status != 1:
			continue
		var boxes := _boxes(row.type, row.entity)
		for part in boxes.size():
			while row.handles.size() <= part:
				row.handles.append(-2 - context.shapes.size())
				context.shapes.append({"row": row, "part": row.handles.size() - 1})
			result.append(
				{"handle": row.handles[part], "mode": row.mode, "box": boxes[part], "row": row}
			)
	return result


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
		if row.status != 1 or row.entity.status != 1 or _boxes(row.type, row.entity).is_empty():
			continue
		for box: Array in row.old_boxes:
			if body.y + bounds[3] > box[1] or not _box_overlap(body, bounds, box, 0, S):
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
	body: Dictionary, world: Dictionary, bounds: Array, side: int, one_way := 0
) -> void:
	var context := _context(world)
	if context.is_empty() or not is_same(body, context.state):
		return
	for shape: Dictionary in _shapes(world):
		if shape.mode == 2 and shape.handle != one_way:
			continue
		var row: Dictionary = shape.row
		if not _box_overlap(body, bounds, shape.box) or not row.type.has_method("bump"):
			continue
		var key := "%s:%d" % [row.entity.id, side]
		if context.bumps.has(key):
			continue
		context.bumps[key] = true
		row.type.bump(row.entity, context.state, world, side)


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
	for shape: Dictionary in _shapes(world):
		if is_same(ignore, shape.row.entity):
			continue
		if shape.mode == 2 and top > shape.box[1]:
			continue
		if _box_overlap(probe, bounds, shape.box):
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
