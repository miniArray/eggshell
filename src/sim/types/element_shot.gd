extends RefCounted
## Fire and ice breath. Each heat or cold request from the player's mouth becomes
## a runtime shot that starts 16 px behind the mouth, flies straight at 768 px/s
## for 0.3 s and passes through everything it strikes. Touching solid terrain
## ends it 0.05 s later. Only types that declare element reactions take its hit.

const S := preload("res://src/sim/units.gd").SCALE
const Requests = preload("res://src/sim/move_requests.gd")
const World = preload("res://src/sim/world.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const Elements = preload("res://src/sim/elements.gd")
const Constants = preload("res://src/sim/script_constants.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const CODES := ["fire_shot", "ice_shot"]
const DYNAMIC := true
const STEP_PHASE := 0
const CONTACT_PHASE := -1
const FIELDS := [["heading", 0], ["age", 0], ["wall_ticks", 0]]
const LEVEL_FIELDS := [["element_request_cursor", 0]]
const SPEED := 768 * 60
const BACK := 16 * S
const LIFE_TICKS := 18
const WALL_TICKS := 3
const BOX := [-14 * S, -14 * S, 14 * S, 14 * S]


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func element(entity: Dictionary) -> int:
	return Elements.FIRE if entity.code == CODES[0] else Elements.ICE


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func reset_map(state: Dictionary, _world: Dictionary) -> void:
	state.element_request_cursor = state.get("move_emit_serial", 0)


static func consume_level_requests(state: Dictionary, world: Dictionary) -> void:
	var result := Requests.since(state, state.element_request_cursor)
	state.element_request_cursor = state.move_emit_serial
	if not result.ok:
		return
	for request: Dictionary in result.requests:
		if request.kind == Requests.HEAT:
			spawn(state, world, Elements.FIRE, request.x, request.y, request.angle)
		elif request.kind == Requests.COLD:
			spawn(state, world, Elements.ICE, request.x, request.y, request.angle)


static func spawn(
	state: Dictionary, world: Dictionary, kind: int, x: int, y: int, angle: int
) -> Dictionary:
	var heading: int = posmod(angle, 360000)
	var cosine := Motion.turn_cosine(heading)
	var sine := Motion.turn_sine(heading)
	return registry().spawn_dynamic(
		state,
		world,
		CODES[0] if kind == Elements.FIRE else CODES[1],
		x - BACK * cosine / S,
		y - BACK * sine / S,
		{
			"heading": heading,
			"vx": SPEED * cosine / S,
			"vy": SPEED * sine / S,
			"can_despawn": 1
		}
	)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.age += 1
	if entity.wall_ticks:
		entity.wall_ticks -= 1
		if not entity.wall_ticks:
			entity.status = 3
			return
	if entity.age > LIFE_TICKS:
		entity.status = 3
		return
	entity.x += entity.vx
	entity.y += entity.vy
	if (
		not entity.wall_ticks
		and World.overlaps_box(
			world,
			entity.x + BOX[0],
			entity.y + BOX[1],
			entity.x + BOX[2],
			entity.y + BOX[3]
		)
	):
		entity.wall_ticks = WALL_TICKS
	strike(entity, state, world)


## Strikes every reacting object the shot overlaps. The shot itself continues.
static func strike(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var dispatch := registry()
	var kind := Hits.FIRE if element(entity) == Elements.FIRE else Hits.ICE
	var box := [entity.x + BOX[0], entity.y + BOX[1], entity.x + BOX[2], entity.y + BOX[3]]
	for other: Dictionary in Near.nearby(state, world, box):
		if (
			other.token == entity.token
			or other.status != 1
			or other.get("held", 0)
			or other.get("hidden", 0)
		):
			continue
		var type: Script = dispatch.lookup(other.code)
		if (
			not Constants.read(type, "ELEMENT_REACTIONS", 0)
			or not type.has_method("hit")
			or not dispatch.overlaps_box(other, type, box)
		):
			continue
		type.hit(other, state, world, kind, entity.x)


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "rotation": float(entity.heading) / 1000.0}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.code in CODES
		and entity.heading >= 0
		and entity.heading < 360000
		and entity.age >= 0
		and entity.age <= LIFE_TICKS + 1
		and entity.wall_ticks >= 0
		and entity.wall_ticks <= WALL_TICKS
	)


static func valid_state(state: Dictionary) -> bool:
	return state.get("element_request_cursor") is int and state.element_request_cursor >= 0
