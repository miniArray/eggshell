extends RefCounted
## Stationary inventory items and their saved, fixed-step thrown form.

const CODES := ["o7"]
const DYNAMIC := true
const S := preload("res://src/sim/units.gd").SCALE
const Moves = preload("res://src/sim/moves.gd")
const Life = preload("res://src/sim/life.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Collision = preload("res://src/sim/collision.gd")
const World = preload("res://src/sim/world.gd")
const Motion = preload("res://src/sim/item_motion.gd")
const Math = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const STATIONARY := 0
const THROWN := 1
const FALLING := 2
const FIELDS := [
	["variant", 0],
	["colour", 0],
	["mode", STATIONARY],
	["floating", 0],
	["pickup_delay", 0],
	["despawn_ticks", 0],
	["bounces", 4],
	["fall_on_terrain", 0],
	["camera", 0],
	["last_target", 0],
	["origin_token", 0],
	["loot_created", 0],
	["ignore_terrain", 0]
]
const LEVEL_FIELDS := [
	["egg_request_cursor", 0],
	["egg_colour_0", -1],
	["egg_colour_1", -1],
	["egg_colour_2", -1],
	["egg_colour_3", -1],
	["egg_colour_4", -1],
	["egg_colour_5", -1],
	["egg_origin_0", 0],
	["egg_origin_1", 0],
	["egg_origin_2", 0],
	["egg_origin_3", 0],
	["egg_origin_4", 0],
	["egg_origin_5", 0],
	["egg_ghost_0", 0],
	["egg_ghost_1", 0],
	["egg_ghost_2", 0],
	["egg_ghost_3", 0],
	["egg_ghost_4", 0],
	["egg_ghost_5", 0]
]


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or form not in [0, 1, 2, 3]:
		return {"ok": false, "error": "Unsupported inventory item form"}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {
		"variant": int(source.get("variant", 0)),
		"colour": int(source.get("variant", 0)),
		"spawn_mode": 1,
		"status": 0,
		"can_despawn": 1,
		"can_respawn": 1
	}


static func bounds(entity: Dictionary) -> Array:
	return [-12 * S, -12 * S, 12 * S, (12 if entity.mode == THROWN else 16) * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.pickup_delay = maxi(0, entity.pickup_delay - 1)
	if entity.despawn_ticks:
		entity.despawn_ticks -= 1
		if not entity.despawn_ticks:
			remove(entity, state, world, false)
			return
	if entity.collected:
		return
	if entity.mode == THROWN:
		travel(entity, state, world)
	elif entity.mode == FALLING:
		entity.vy = mini(576 * 60, entity.vy + 1600)
		entity.y += entity.vy
	elif not entity.floating and Motion.fall(entity, world, bounds(entity), 1600, 576 * 60):
		entity.vx = 0
	var box := bounds(entity)
	for name: String in ["lava", "lava_3"]:
		if World.named_overlaps(
			world, name, entity.x + box[0], entity.y + box[1], entity.x + box[2], entity.y + box[3]
		):
			remove(entity, state, world, false)
			return


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, _input: int) -> void:
	if (
		entity.mode != STATIONARY
		or entity.collected
		or entity.pickup_delay
		or Life.blocks_step(state)
	):
		return
	var box := Moves.player_box(state)
	if registry().overlaps_box(
		entity,
		registry().lookup("o7"),
		[state.x + box[0], state.y + box[1], state.x + box[2], state.y + box[3]]
	):
		grant(entity, state, world)


static func grant(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	consume_level_requests(state, world)
	var queue := inventory(state)
	if queue.size() == 6:
		mark_origin(state, queue.pop_front().origin)
	queue.append(
		{
			"colour": entity.colour,
			"origin": entity.token if entity.source_index >= 0 else entity.origin_token,
			"ignore_terrain": entity.ignore_terrain
		}
	)
	Moves.give_eggs(state, 1)
	write_inventory(state, queue)
	if entity.origin_token:
		var origin: Dictionary = registry().find_token(state, entity.origin_token)
		if not origin.is_empty() and not (origin.code == "o7" and origin.variant == 3):
			origin.collected = 1
	entity.status = 3
	entity.can_respawn = 0
	# Ordinary inventory items return on a map reset; only the special form has a persistent flag.


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if entity.collected or entity.mode == FALLING:
		return 0
	entity.mode = STATIONARY
	entity.floating = 0
	entity.camera = 0
	entity.vy = -384 * 60
	entity.vx = (-256 if entity.x >= state.x else 256) * 60
	return 2


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind == Hits.BUMP and entity.mode == STATIONARY and not entity.collected:
		entity.floating = 0
		entity.vy = -384 * 60


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func active_count(state: Dictionary) -> int:
	var count: int = state.move_eggs
	for entity: Dictionary in state.entities:
		if entity.code != "o7" or entity.status != 1 or entity.collected:
			continue
		var box := bounds(entity)
		if (
			entity.x + box[2] > state.camera_x - 416 * S
			and entity.x + box[0] < state.camera_x + 416 * S
			and entity.y + box[3] > state.camera_y - 224 * S
			and entity.y + box[1] < state.camera_y + 224 * S
		):
			count += 1
	return count


static func consume_level_requests(state: Dictionary, world: Dictionary) -> void:
	var result := Requests.since(state, state.egg_request_cursor)
	if not result.ok:
		# A lifetime reset also resets the move sequence. No old token may be replayed.
		state.egg_request_cursor = state.move_emit_serial
		normalize_inventory(state, state.move_eggs)
		return
	var before: int = state.move_eggs
	for request: Dictionary in result.requests:
		if request.kind == Requests.EGG:
			before += 1
		elif request.kind == Requests.STORED_EGG:
			before -= 1
	normalize_inventory(state, maxi(before, inventory(state).size()))
	for request: Dictionary in result.requests:
		var queue := inventory(state)
		if request.kind == Requests.EGG:
			var item: Dictionary = (
				queue.pop_front() if not queue.is_empty() else {"colour": 0, "origin": 0}
			)
			var vx: int = request.vx
			var vy: int = request.vy
			if not vx and not vy:
				vx = Math.sine((request.angle + 450000) % 360000, 360000, 1024 * 60)
				vy = Math.sine((request.angle + 360000) % 360000, 360000, 1024 * 60)
			registry().spawn_dynamic(
				state,
				world,
				"o7",
				request.x,
				request.y,
				{
					"mode": THROWN,
					"colour": item.colour,
					"variant": item.colour,
					"origin_token": item.origin,
					"ignore_terrain": item.get("ignore_terrain", 0),
					"vx": vx,
					"vy": vy
				}
			)
		elif request.kind == Requests.STORED_EGG:
			if queue.size() == 6:
				mark_origin(state, queue.pop_front().origin)
			queue.append({"colour": 0, "origin": 0})
		write_inventory(state, queue)
	state.egg_request_cursor = result.latest
	normalize_inventory(state, state.move_eggs)


static func inventory(state: Dictionary) -> Array:
	var result := []
	for slot in 6:
		if state["egg_colour_%d" % slot] >= 0:
			result.append(
				{
					"colour": state["egg_colour_%d" % slot],
					"origin": state["egg_origin_%d" % slot],
					"ignore_terrain": state["egg_ghost_%d" % slot]
				}
			)
	return result


static func write_inventory(state: Dictionary, queue: Array) -> void:
	for slot in 6:
		state["egg_colour_%d" % slot] = queue[slot].colour if slot < queue.size() else -1
		state["egg_origin_%d" % slot] = queue[slot].origin if slot < queue.size() else 0
		state["egg_ghost_%d" % slot] = (
			queue[slot].get("ignore_terrain", 0) if slot < queue.size() else 0
		)


static func normalize_inventory(state: Dictionary, count: int) -> void:
	var queue := inventory(state)
	var target := clampi(count, 0, 6)
	while queue.size() > target:
		queue.pop_back()
	while queue.size() < target:
		queue.append({"colour": 0, "origin": 0})
	write_inventory(state, queue)


static func reset_map(state: Dictionary, _world: Dictionary) -> void:
	state.egg_request_cursor = state.move_emit_serial
	for slot in 6:
		state["egg_origin_%d" % slot] = 0


static func travel(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var steps := maxi(1, (maxi(absi(entity.vx), absi(entity.vy)) + S - 1) / S)
	for index in steps:
		var dx: int = entity.vx * (index + 1) / steps - entity.vx * index / steps
		var dy: int = entity.vy * (index + 1) / steps - entity.vy * index / steps
		var contact := object_collisions(entity, state, world, dx, dy)
		if not contact.alive:
			return
		if contact.redirected:
			dx = entity.vx * (index + 1) / steps - entity.vx * index / steps
			dy = entity.vy * (index + 1) / steps - entity.vy * index / steps
		var vx: int = entity.vx
		var vy: int = entity.vy
		var box := bounds(entity)
		var x: int = entity.x
		var y: int = entity.y
		Collision.horizontal(entity, world, box, dx, 0)
		var horizontal: bool = entity.x - x != dx
		Collision.vertical(entity, world, box, dy, 0)
		var vertical: bool = entity.y - y != dy
		var preserved := preserve_solid_bounce(entity, box, x, y, dx, dy, contact.solids)
		horizontal = horizontal or preserved[0]
		vertical = vertical or preserved[1]
		entity.vx = -vx if horizontal else vx
		entity.vy = -vy if vertical else vy
		if horizontal or vertical:
			entity.bounces = maxi(-9223372036854775806, entity.bounces - 1)
			if entity.colour < 2:
				entity.colour += 1
			if entity.bounces == 0 and entity.fall_on_terrain:
				entity.mode = FALLING
				entity.vx = 0
				entity.vy = 0
				return
		if entity.mode != THROWN or entity.status != 1:
			return


static func object_collisions(
	entity: Dictionary, state: Dictionary, world: Dictionary, dx: int, dy: int
) -> Dictionary:
	var result := {"alive": true, "redirected": false, "solids": []}
	var dispatch := registry()
	var box := bounds(entity)
	var probe := [
		entity.x + box[0] + dx,
		entity.y + box[1] + dy,
		entity.x + box[2] + dx,
		entity.y + box[3] + dy
	]
	var last: Dictionary = dispatch.find_token(state, entity.last_target)
	if last.is_empty() or not dispatch.overlaps_box(last, dispatch.lookup(last.code), probe):
		entity.last_target = 0
	for other: Dictionary in state.entities:
		if (
			other.token == entity.token
			or other.token == entity.last_target
			or other.status != 1
			or other.collected
			or other.get("held", 0) == 1
			or other.get("hidden", 0) == 1
		):
			continue
		var type: Script = dispatch.lookup(other.code)
		if not dispatch.overlaps_box(other, type, probe):
			continue
		if type.has_method("touches") and not type.touches(other, probe):
			continue
		var old_shapes := solid_shapes(type, other)
		var response := 0
		if type.has_method("projectile_contact"):
			response = type.projectile_contact(other, entity, state, world)
		elif type.has_method("hit"):
			type.hit(other, state, world, Hits.EGG, entity.x)
			response = 1
		if response == 1:
			remove(entity, state, world, true)
			result.alive = false
			return result
		if response == 2:
			result.redirected = true
		if response == 3:
			# A solid's last hit still has its pre-destruction bounce. Non-solids pierce.
			result.solids.append_array(old_shapes)
		if response in [2, 3]:
			entity.last_target = other.token
	return result


static func solid_shapes(type: Script, entity: Dictionary) -> Array:
	var mode := int(type.get_script_constant_map().get("SOLID", 0))
	if mode not in [1, 2]:
		return []
	var boxes: Array = registry().solid_boxes(entity, type)
	var result := []
	for box: Array in boxes:
		if box.size() == 4:
			result.append({"box": box.duplicate(), "mode": mode})
	return result


static func preserve_solid_bounce(
	entity: Dictionary, body: Array, x: int, y: int, dx: int, dy: int, shapes: Array
) -> Array:
	var horizontal := false
	var vertical := false
	for shape: Dictionary in shapes:
		var box: Array = shape.box
		if shape.mode == 1 and dx and rect_overlap(x + dx, y, body, box):
			entity.x = box[0] - body[2] - 1 if dx > 0 else box[2] - body[0] + 1
			horizontal = true
		if dy and rect_overlap(entity.x, y + dy, body, box):
			if shape.mode == 1 or dy > 0 and y + body[3] <= box[1]:
				entity.y = box[1] - body[3] - 1 if dy > 0 else box[3] - body[1] + 1
				vertical = true
	return [horizontal, vertical]


static func rect_overlap(x: int, y: int, body: Array, box: Array) -> bool:
	return (
		x + body[2] >= box[0]
		and x + body[0] <= box[2]
		and y + body[3] >= box[1]
		and y + body[1] <= box[3]
	)


static func remove(
	entity: Dictionary, state: Dictionary, world: Dictionary, with_loot: bool
) -> void:
	entity.status = 3
	mark_origin(state, entity.origin_token)
	if with_loot and entity.mode == THROWN and not entity.loot_created:
		entity.loot_created = 1
		loot(entity, state, world)


static func deactivate(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	mark_origin(state, entity.origin_token)


static func mark_origin(state: Dictionary, token: int) -> void:
	var original: Dictionary = registry().find_token(state, token)
	if not original.is_empty() and original.code == "o7" and original.variant == 3:
		original.collected = 1


static func loot(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var dispatch := registry()
	if entity.colour in [1, 3]:
		dispatch.spawn_dynamic(
			state,
			world,
			"o2" if entity.colour == 3 else "o1",
			entity.x,
			entity.y,
			{
				"moving": 1,
				"despawn_ticks": 480,
				"pickup_delay": 30,
				"vx": (-176 if entity.x >= state.x else 176) * 60,
				"vy": -Math.random_ticks(state, 256 * 60, 512 * 60)
			}
		)
	elif entity.colour == 2:
		for index in 2:
			if state.health + index < 30:
				dispatch.spawn_dynamic(
					state,
					world,
					"o4",
					entity.x,
					entity.y,
					{
						"vy": -Math.random_ticks(state, 256 * 60, 384 * 60),
						"facing": -1 if Math.random_ticks(state, 0, 1) == 0 else 1,
						"despawn_ticks": 480,
						"max_speed": Math.random_ticks(state, 64 * 60, 128 * 60)
					}
				)
			else:
				dispatch.spawn_dynamic(
					state,
					world,
					"o1",
					entity.x,
					entity.y,
					{
						"moving": 1,
						"despawn_ticks": 480,
						"pickup_delay": 30,
						"vx": Math.random_ticks(state, -192 * 60, 192 * 60),
						"vy": -Math.random_ticks(state, 256 * 60, 384 * 60)
					}
				)


static func view_state(entity: Dictionary, state: Dictionary) -> Dictionary:
	# The four literal animation names select the inventory colours.
	return {
		"visible": entity.status == 1 and not entity.collected,
		"animation": ["Green", "Yellow", "Red", "Purple"][entity.colour],
		"modulate_alpha":
		(
			0.0
			if entity.despawn_ticks > 0 and entity.despawn_ticks < 180 and state.frame % 12 < 6
			else 1.0
		)
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.variant >= 0
		and entity.variant <= 3
		and entity.colour >= 0
		and entity.colour <= 3
		and entity.mode in [STATIONARY, THROWN, FALLING]
		and entity.floating in [0, 1]
		and entity.ignore_terrain in [0, 1]
		and entity.pickup_delay >= 0
		and entity.despawn_ticks >= 0
		and entity.bounces <= 4
		and entity.fall_on_terrain in [0, 1]
		and entity.camera in [0, 1]
		and entity.last_target >= 0
		and entity.origin_token >= 0
		and entity.loot_created in [0, 1]
		and entity.vx >= -1024 * 60
		and entity.vx <= 1024 * 60
		and entity.vy >= -1024 * 60
		and entity.vy <= 1024 * 60
	)


static func valid_state(state: Dictionary) -> bool:
	for pair: Array in LEVEL_FIELDS:
		if not state.get(pair[0]) is int:
			return false
	if state.egg_request_cursor < 0:
		return false
	var empty := false
	for slot in 6:
		var colour: int = state["egg_colour_%d" % slot]
		var origin: int = state["egg_origin_%d" % slot]
		var ghost: int = state["egg_ghost_%d" % slot]
		if (
			colour < -1
			or colour > 3
			or origin < 0
			or ghost not in [0, 1]
			or colour == -1 and (origin != 0 or ghost != 0)
		):
			return false
		if colour == -1:
			empty = true
		elif empty:
			return false
	return true
