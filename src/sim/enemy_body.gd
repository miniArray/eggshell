extends RefCounted
## Saved food, spit and impact state shared by enemy families.

const Moves = preload("res://src/sim/moves.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const Damage = preload("res://src/sim/damage.gd")
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const World = preload("res://src/sim/world.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const FREE := 0
const HELD := 1
const RELEASED := 2
const GONE := 3
const FIELDS := [
	["hidden", 0],
	["held", 0],
	["request_cursor", 0],
	["spat", 0],
	["spit_age", 0],
	["spit_speed", 0],
	["spit_wall", 0],
	["impact_cursor", 0],
	["variant", 0],
	["mirror", 0],
	["spawn_x", 0],
	["spawn_y", 0],
	["started", 0]
]


static func create(source: Dictionary) -> Dictionary:
	var dynamic: bool = int(source.get("source_index", 0)) == -1
	return {
		"variant": int(source.get("variant", 0)),
		"mirror": int(source.get("mirror", 0)),
		"spawn_x": int(source.x),
		"spawn_y": int(source.y),
		"vx": Options.option(source, "vx"),
		"vy": Options.option(source, "vy"),
		"facing": Options.option(source, "facing", 1 if source.get("mirror", 0) == 1 else -1),
		"spawn_mode": 0 if dynamic else 1,
		"status": 1 if dynamic else 0,
		"can_despawn": 1,
		"can_respawn": 0 if dynamic else 1,
		"layer": 8
	}


static func process(entity: Dictionary, state: Dictionary) -> int:
	if not entity.started:
		entity.started = 1
		entity.impact_cursor = int(state.get("move_impact", 0))
		if entity.mirror == 2:
			entity.facing = 1 if state.x > entity.x else -1
	var result := Requests.since(state, entity.request_cursor)
	var released := false
	if result.ok:
		for request: Dictionary in result.requests:
			if request.item != entity.get("token", 0):
				continue
			if request.kind == Requests.CONSUME:
				remove(entity, state)
			elif request.kind == Requests.SPIT and entity.held:
				entity.held = 0
				entity.spat = 1
				entity.spit_age = 0
				entity.spit_wall = 0
				entity.x = request.x
				entity.y = request.y
				entity.vx = request.vx
				entity.vy = request.vy
				entity.spit_speed = absi(request.vx)
				if request.vx:
					entity.facing = signi(request.vx)
				released = true
	entity.request_cursor = int(state.get("move_emit_serial", 0))
	if entity.status == 3:
		return GONE
	if entity.held:
		entity.x = state.x + state.facing * 24 * S
		entity.y = state.y - 24 * S
		entity.vx = 0
		entity.vy = 0
		return HELD
	return RELEASED if released else FREE


static func tongue(
	entity: Dictionary, state: Dictionary, digestible: int = 1, instant: int = 0
) -> int:
	if entity.hidden or entity.held or entity.status != 1:
		return 0
	if Moves.catch_item(state, int(entity.get("token", 0)), digestible, 0, 0, instant):
		entity.held = 1
		entity.spat = 0
		entity.vx = 0
		entity.vy = 0
		entity.request_cursor = state.move_emit_serial
		return 1
	return 0


static func spit_step(
	entity: Dictionary, state: Dictionary, world: Dictionary, bounds: Array
) -> bool:
	if not entity.spat:
		return false
	entity.spit_age += 1
	entity.vx = entity.facing * entity.spit_speed
	var distance: int = entity.vx
	var actual := Motion.move(entity, world, bounds, distance, true)
	if actual != distance:
		entity.facing *= -1
		entity.spit_speed = 48 * 60
		entity.spit_wall = 1
		entity.spit_age = 0
	var landed := Motion.gravity_box(entity, world, bounds)
	var duration := 42 if entity.spit_wall else 60
	if landed:
		if entity.spit_age < duration:
			var remaining: int = duration - entity.spit_age
			var high := 256 if entity.spit_wall else 512
			var low := 96 if entity.spit_wall else 128
			var bounce: int = (
				low * 60 + (high - low) * 60 * remaining * remaining / (duration * duration)
			)
			entity.vy = -bounce / 2 - 128 * 60
		else:
			entity.spat = 0
			entity.vx = 0
			entity.facing = 1 if entity.x < state.x else -1
	if not hazards(entity, state, world, bounds):
		hit_others(entity, state, world, bounds, Hits.SPIT, true)
	return true


static func overlap(a: Array, b: Array) -> bool:
	return (
		a.size() == 4
		and b.size() == 4
		and a[0] < b[2]
		and a[2] > b[0]
		and a[1] < b[3]
		and a[3] > b[1]
	)


static func polygon_overlap(hull: Array, box: Array) -> bool:
	if box.size() != 4 or hull.size() < 3:
		return false
	var axes := [[1, 0], [0, 1]]
	for index: int in hull.size():
		var a: Array = hull[index]
		var b: Array = hull[(index + 1) % hull.size()]
		axes.append([a[1] - b[1], b[0] - a[0]])
	for axis: Array in axes:
		var minimum: int = hull[0][0] * axis[0] + hull[0][1] * axis[1]
		var maximum := minimum
		for point: Array in hull:
			var dot: int = point[0] * axis[0] + point[1] * axis[1]
			minimum = mini(minimum, dot)
			maximum = maxi(maximum, dot)
		var rectangle_min: int = (
			box[0 if axis[0] >= 0 else 2] * axis[0] + box[1 if axis[1] >= 0 else 3] * axis[1]
		)
		var rectangle_max: int = (
			box[2 if axis[0] >= 0 else 0] * axis[0] + box[3 if axis[1] >= 0 else 1] * axis[1]
		)
		if maximum <= rectangle_min or rectangle_max <= minimum:
			return false
	return true


static func world_box(entity: Dictionary, bounds: Array) -> Array:
	return [entity.x + bounds[0], entity.y + bounds[1], entity.x + bounds[2], entity.y + bounds[3]]


static func player_overlap(entity: Dictionary, state: Dictionary, bounds: Array) -> bool:
	if (
		entity.hidden
		or entity.held
		or entity.spat
		or entity.status != 1
		or state.get("captured_by", 0)
	):
		return false
	return overlap(world_box(entity, bounds), world_box(state, Moves.player_box(state)))


static func impact_on_top(entity: Dictionary, state: Dictionary, bounds: Array) -> bool:
	var impact := Moves.impact_request(state)
	if impact.is_empty() or impact.serial <= entity.impact_cursor:
		return false
	entity.impact_cursor = impact.serial
	if not pounding(state) or entity.held or entity.spat:
		return false
	var box := world_box(entity, bounds)
	var player := Moves.player_box(state)
	return (
		impact.x + player[2] > box[0]
		and impact.x + player[0] < box[2]
		and absi(impact.y - box[1]) <= 1
	)


static func pounding(state: Dictionary) -> bool:
	return state.move_action in [Moves.POUND_FALL, Moves.POUND_LAND]


static func bounce(entity: Dictionary, state: Dictionary, input: int) -> void:
	Moves.bounce(state, -absi(entity.vy / 2) - 320 * 60, input)


static func hurt(entity: Dictionary, state: Dictionary) -> void:
	Damage.hurt(state, entity.x)


static func remove(entity: Dictionary, state: Dictionary = {}) -> void:
	if not state.is_empty() and entity.status != 3:
		var registry: Script = registry_for()
		var type: Script = registry.lookup(entity.code)
		if type.has_method("on_remove"):
			type.on_remove(entity, state)
	entity.status = 3
	entity.held = 0
	entity.spat = 0
	entity.can_respawn = 0


static func hazards(
	entity: Dictionary, state: Dictionary, world: Dictionary, bounds: Array
) -> bool:
	var box := world_box(entity, bounds)
	for name: String in ["lava", "lava_3"]:
		if World.named_overlaps(world, name, box[0], box[1], box[2], box[3]):
			remove(entity, state)
			return true
	return false


static func hit_others(
	entity: Dictionary,
	state: Dictionary,
	world: Dictionary,
	bounds: Array,
	kind: int,
	self_breaks: bool = false
) -> void:
	var registry: Script = registry_for()
	var box := world_box(entity, bounds)
	for other: Dictionary in state.entities:
		if (
			other.id == entity.id
			or other.status != 1
			or other.get("held", 0)
			or other.get("hidden", 0)
		):
			continue
		var type: Script = registry.lookup(other.code)
		if (
			not type.has_method("bounds")
			or not (type.has_method("hit") or type.has_method("projectile_contact"))
		):
			continue
		if overlap(box, world_box(other, type.bounds(other))):
			var reaction := 0
			if (
				type.has_method("projectile_contact")
				and type.get_script_constant_map().get("ENEMY", false)
			):
				reaction = type.projectile_contact(other, entity, state, world)
			elif type.has_method("hit"):
				type.hit(other, state, world, kind, entity.x)
				reaction = 3
			if entity.status != 1:
				return
			if reaction == 1 or (self_breaks and reaction == 3):
				remove(entity, state)
				return


static func begin_overlap(
	a: Dictionary, b: Dictionary, state: Dictionary, world: Dictionary
) -> bool:
	for pair: Dictionary in state.entities:
		if (
			pair.code == "enemy_overlap"
			and pair.status == 1
			and pair.a == a.token
			and pair.b == b.token
		):
			return false
	var registry: Script = registry_for()
	var pair: Dictionary = registry.spawn_dynamic(
		state, world, "enemy_overlap", a.x, a.y, {"a": a.token, "b": b.token}
	)
	return not pair.is_empty()


static func projectile_kind(projectile: Dictionary) -> int:
	if projectile.has("fall_on_terrain"):
		return Hits.EGG
	if projectile.get("spat", 0):
		return Hits.SPIT
	var registry: Script = registry_for()
	var type: Script = registry.lookup(projectile.code)
	return int(type.get_script_constant_map().get("HIT_KIND", Hits.SPIT))


static func strike_wall(
	entity: Dictionary,
	state: Dictionary,
	world: Dictionary,
	bounds: Array,
	direction: int,
	kind: int
) -> void:
	var registry: Script = registry_for()
	var box := world_box(entity, bounds)
	box[0 if direction < 0 else 2] += direction * 2 * S
	for other: Dictionary in state.entities:
		if other.id == entity.id or other.status != 1:
			continue
		var type: Script = registry.lookup(other.code)
		if type.get_script_constant_map().get("SOLID", 0) != 1 or not type.has_method("hit"):
			continue
		if overlap(box, type.solid_box(other)):
			type.hit(other, state, world, kind, entity.x)


static func valid(entity: Dictionary) -> bool:
	return (
		entity.hidden in [0, 1]
		and entity.held in [0, 1]
		and entity.spat in [0, 1]
		and entity.spit_wall in [0, 1]
		and entity.started in [0, 1]
		and entity.request_cursor >= 0
		and entity.impact_cursor >= 0
		and entity.spit_age >= 0
		and entity.spit_age <= 1_000_000
		and entity.spit_speed >= 0
		and entity.spit_speed <= Options.MAX_SPEED
		and entity.variant >= 0
		and entity.variant <= 4
		and entity.mirror in [0, 1, 2]
		and entity.vx >= -Options.MAX_SPEED
		and entity.vx <= Options.MAX_SPEED
		and entity.vy >= Options.MIN_VERTICAL
		and entity.vy <= Options.MAX_VERTICAL
		and not (entity.held and entity.spat)
	)


static func registry_for(world: Dictionary = {}) -> Script:
	# Resolve after type loading to avoid a registry/type import cycle.
	var bound: Variant = Collision.registry_for(world)
	return bound if bound is Script else load("res://src/sim/registry.gd")
