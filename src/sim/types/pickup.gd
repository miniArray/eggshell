extends RefCounted
## Counter pickups keep their collection flag in the canonical entity table.

const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Motion = preload("res://src/sim/item_motion.gd")
const Math = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o1", "o2", "o3"]
const DYNAMIC := true
const FIELDS := [
	["dotted", 0],
	["enabled", 1],
	["collect_ticks", 0],
	["collect_y", 0],
	["phase", 0],
	["moving", 0],
	["bounce_done", 0],
	["pickup_delay", 0],
	["despawn_ticks", 0],
	["held", 0],
	["request_cursor", 0],
	["origin_token", 0]
]
const FLOWER_POINTS := [-22, -22, 0, -32, 21, -22, 31, 0, 23, 23, 0, 31, -22, 21, -32, 0]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	if source.code != "o3":
		var value: Variant = source.properties.get("F", 0)
		if not (value is int or value is float) or not is_finite(value) or value != floor(value):
			return {"ok": false, "error": "Invalid coin form"}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var dotted := int(source.code != "o3" and source.get("variant", 0) == 1)
	return {"dotted": dotted, "enabled": 1 - dotted, "collect_y": int(source.y)}


static func bounds(entity: Dictionary) -> Array:
	if entity.code == "o3":
		return [-32 * S, -32 * S, 32 * S, 32 * S]
	var half_width: int = [12, 8, 4, 8][(entity.phase * 8 / 60) % 4] * S
	return [-half_width, -16 * S, half_width, 16 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.phase = (entity.phase + 1) % 60
	if entity.held:
		consume_requests(entity, state, world)
		return
	if entity.collect_ticks:
		entity.collect_ticks -= 1
		var elapsed: int = 60 - entity.collect_ticks
		entity.y = entity.collect_y - Math.sine(elapsed, 240, 96 * S)
		if not entity.collect_ticks:
			entity.status = 3
	elif entity.moving and not entity.collected:
		entity.pickup_delay = maxi(0, entity.pickup_delay - 1)
		entity.vx = Motion.approach(entity.vx, 0, 128)
		if Motion.fall(entity, world, bounds(entity), 2048, 704 * 60):
			if entity.code == "o2":
				entity.vy = -192 * 60
			elif not entity.bounce_done:
				entity.vy = -384 * 60
			entity.bounce_done = 1
		if entity.despawn_ticks:
			entity.despawn_ticks -= 1
			if not entity.despawn_ticks:
				entity.status = 3


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	var body := Moves.player_box(state)
	if touches(
		entity, [state.x + body[0], state.y + body[1], state.x + body[2], state.y + body[3]]
	):
		collect(entity, state)


static func touches(entity: Dictionary, box: Array) -> bool:
	if entity.collected or not entity.enabled or entity.held or entity.pickup_delay:
		return false
	var rect := bounds(entity)
	if (
		entity.x + rect[2] <= box[0]
		or entity.x + rect[0] >= box[2]
		or entity.y + rect[3] <= box[1]
		or entity.y + rect[1] >= box[3]
	):
		return false
	if entity.code != "o3":
		return true
	var angle := Math.sine(entity.phase, 60, 10000)
	var sin_angle := Math.sine((angle + 360000) % 360000, 360000, S)
	var cos_angle := Math.sine((angle + 450000) % 360000, 360000, S)
	var points := PackedInt64Array()
	for index in range(0, FLOWER_POINTS.size(), 2):
		points.append(FLOWER_POINTS[index] * cos_angle - FLOWER_POINTS[index + 1] * sin_angle)
		points.append(FLOWER_POINTS[index] * sin_angle + FLOWER_POINTS[index + 1] * cos_angle)
	return Polygon.overlaps_box(
		points, box[0] - entity.x, box[1] - entity.y, box[2] - entity.x, box[3] - entity.y
	)


static func collect(entity: Dictionary, state: Dictionary) -> void:
	if entity.collected or not entity.enabled or entity.pickup_delay:
		return
	var kind := (
		Life.FLOWER
		if entity.code == "o3"
		else (Life.RED_COIN if entity.code == "o2" else Life.COIN)
	)
	if Life.collect(state, kind, entity):
		if entity.origin_token:
			var registry: Script = load("res://src/sim/registry.gd")
			var origin: Dictionary = registry.find_token(state, entity.origin_token)
			if not origin.is_empty():
				origin.collected = 1
		entity.held = 0
		if entity.code == "o2":
			entity.phase = 0
			entity.collect_y = entity.y
			entity.collect_ticks = 60
		else:
			entity.status = 3


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind in [Hits.EGG, Hits.SHELL, Hits.SPIT]:
		collect(entity, state)


static func projectile_contact(
	entity: Dictionary, _projectile: Dictionary, state: Dictionary, _world: Dictionary
) -> int:
	if entity.collected or not entity.enabled or entity.pickup_delay:
		return 0
	collect(entity, state)
	return 1 if entity.code == "o3" else 3


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	if not entity.moving or entity.collected or entity.pickup_delay or Life.blocks_step(state):
		return 0
	if Moves.catch_item(state, entity.token, 0, 0, 0, 1):
		entity.held = 1
		entity.request_cursor = state.move_emit_serial
		return 1
	return 0


static func consume_requests(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if not entity.held:
		return
	var requests := Requests.since(state, entity.request_cursor)
	if not requests.ok:
		entity.request_cursor = state.move_emit_serial
		return
	for request: Dictionary in requests.requests:
		if request.item != entity.token:
			continue
		if request.kind == Requests.CONSUME:
			collect(entity, state)
		elif request.kind == Requests.SPIT:
			entity.held = 0
			entity.x = request.x
			entity.y = request.y
			entity.vx = request.vx
			entity.vy = request.vy
	entity.request_cursor = requests.latest


static func toggle(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	if entity.code == "o3" or entity.moving:
		return
	entity.phase = 0
	if entity.dotted and not entity.collected:
		entity.enabled = 1 - entity.enabled


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	# Literal names select ordinary, dotted and collected forms in the pack.
	var animation := "Animation 1"
	if entity.code != "o3":
		animation = "Red" if entity.code == "o2" else "Yellow"
		if entity.collected:
			animation = "RedCollected"
		elif not entity.enabled:
			animation = "RedDotted" if entity.code == "o2" else "Dotted"
	var period := 6 if entity.despawn_ticks < 120 else 12
	return {
		"visible":
		(
			entity.status == 1
			and not entity.held
			and (not entity.collected or entity.collect_ticks > 0)
		),
		"animation": animation,
		"frame": 0 if entity.code == "o3" else (entity.phase * 8 / 60) % 4,
		"rotation": Math.sine(entity.phase, 60, 10000) / 1000.0 if entity.code == "o3" else 0.0,
		"modulate_alpha":
		(
			0.0
			if (
				entity.despawn_ticks > 0
				and entity.despawn_ticks < 240
				and entity.despawn_ticks % period >= period / 2
			)
			else 1.0
		),
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.dotted in [0, 1]
		and entity.enabled in [0, 1]
		and entity.collect_ticks >= 0
		and entity.collect_ticks <= 60
		and (not entity.collect_ticks or entity.code == "o2" and entity.collected == 1)
		and entity.phase >= 0
		and entity.phase < 60
		and entity.moving in [0, 1]
		and entity.bounce_done in [0, 1]
		and entity.pickup_delay >= 0
		and entity.despawn_ticks >= 0
		and entity.held in [0, 1]
		and entity.request_cursor >= 0
		and entity.origin_token >= 0
		and entity.vx >= -1024 * 60
		and entity.vx <= 1024 * 60
		and entity.vy >= -1024 * 60
		and entity.vy <= 1024 * 60
	)
