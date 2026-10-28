extends RefCounted
## Seeds spat by the player. Each seed request becomes a runtime seed that flies
## straight at 768 px/s, strikes the first object it reaches and stops at solids.

const S := preload("res://src/sim/units.gd").SCALE
const Requests = preload("res://src/sim/move_requests.gd")
const Collision = preload("res://src/sim/collision.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const Near = preload("res://src/sim/types/near_query.gd")
const CODES := ["seed_shot"]
const DYNAMIC := true
const HIT_KIND := Hits.SPIT
const STEP_PHASE := 0
const CONTACT_PHASE := -1
const FIELDS := [["heading", 0]]
const LEVEL_FIELDS := [["seed_request_cursor", 0]]
const SPEED := 768 * 60
const BOX := [-4 * S, -4 * S, 4 * S, 4 * S]


static func registry() -> Script:
	return load("res://src/sim/registry.gd")


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func reset_map(state: Dictionary, _world: Dictionary) -> void:
	state.seed_request_cursor = state.get("move_emit_serial", 0)


static func consume_level_requests(state: Dictionary, world: Dictionary) -> void:
	var result := Requests.since(state, state.seed_request_cursor)
	state.seed_request_cursor = state.move_emit_serial
	if not result.ok:
		return
	for request: Dictionary in result.requests:
		if request.kind != Requests.SEED:
			continue
		var heading: int = posmod(request.angle, 360000)
		registry().spawn_dynamic(
			state,
			world,
			CODES[0],
			request.x,
			request.y,
			{
				"heading": heading,
				"vx": SPEED * Motion.turn_cosine(heading) / S,
				"vy": SPEED * Motion.turn_sine(heading) / S,
				"can_despawn": 1
			}
		)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	entity.x += entity.vx
	entity.y += entity.vy
	if Collision.overlaps(entity, world, BOX):
		entity.status = 3  # A stopped seed drops away without touching anything.
		return
	strike(entity, state, world)


static func strike(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	var dispatch := registry()
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
		if not dispatch.overlaps_box(other, type, box):
			continue
		var reaction := 0
		# As with spat bodies: enemies choose their reaction, other objects take a hit.
		if (
			type.has_method("projectile_contact")
			and type.get_script_constant_map().get("ENEMY", false)
		):
			reaction = type.projectile_contact(other, entity, state, world)
		elif type.has_method("hit"):
			type.hit(other, state, world, HIT_KIND, entity.x)
			reaction = 3
		if reaction:
			entity.status = 3
			return


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "rotation": float(entity.heading) / 1000.0}


static func valid(entity: Dictionary) -> bool:
	return entity.heading >= 0 and entity.heading < 360000


static func valid_state(state: Dictionary) -> bool:
	return state.get("seed_request_cursor") is int and state.seed_request_cursor >= 0
