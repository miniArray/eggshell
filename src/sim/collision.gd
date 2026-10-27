extends RefCounted
## Terrain movement for integer actor boxes. A support is -1 for terrain,
## zero for air, or a one-based bridge index. No contact cache is mutable state.
## Movement clears blocked velocity components and cancels slow ramp falls.

const World = preload("res://src/sim/world.gd")
const S := 3600
const DEFAULT_JUMP := 776 * 60


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
	return bridge > 0 and bridge_overlap(body, world.bridges[bridge - 1], bounds, dx, dy)


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
	return found


static func floor_at(body: Dictionary, world: Dictionary, bounds: Array) -> int:
	# A nearby wall is not a floor if the actor already overlaps it.
	if overlaps(body, world, bounds):
		return 0
	if overlaps(body, world, bounds, 0, S):
		return -1
	for index in world.bridges.size():
		var bridge: Dictionary = world.bridges[index]
		if body.y + bounds[3] <= bridge.top and bridge_overlap(body, bridge, bounds, 0, S):
			return index + 1
	return 0


static func track_floor(body: Dictionary, world: Dictionary, bounds: Array) -> int:
	var support := floor_at(body, world, bounds)
	if support > 0 and body.y + bounds[3] == world.bridges[support - 1].top:
		# Exact top contact can occur at spawn or when restoring an older state.
		push_out(body, world, bounds, 0, -1, 2 * S, support)
	if support != 0 and body.vy > 0:
		refine(body, world, bounds, 0, -1, maxi(0, support))
		body.vy = 0
	return support


static func by_wall(body: Dictionary, world: Dictionary, bounds: Array, direction: int) -> bool:
	return (
		overlaps(body, world, bounds, direction * S, 0)
		and overlaps(body, world, bounds, direction * S, -S)
	)


static func prepare(body: Dictionary, world: Dictionary, bounds: Array) -> bool:
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
	if not obstacle and support > 0:
		for index in bridges_at(body, world, bounds):
			if index not in old_bridges:
				bridge = index
				break
	if obstacle or bridge:
		var climb := absi(distance) + 2 * S
		if not wall and push_out(body, world, bounds, 0, -1, climb, bridge):
			if not jumping and absi(body.vy) < absi(jump_speed / 4):
				body.vy = 0
		else:
			var retreat := maxi(absi(distance) * 5 / 2, bounds[2] - bounds[0])
			if push_out(body, world, bounds, -direction, 0, retreat):
				if support < 0 and bridge == 0:
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
			refine(body, world, bounds, 0, -1, maxi(0, floor))
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
	if obstacle or bridge:
		var limit := maxi(absi(distance) * (20 if bridge else 11) / 10, 2 * S)
		if not push_out(body, world, bounds, 0, 1 if distance < 0 else -1, limit, bridge):
			body.y = start_y
		body.vy = 0
	return body.y - start_y


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
