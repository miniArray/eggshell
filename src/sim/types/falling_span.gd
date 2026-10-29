extends RefCounted
## A cancelable standing delay followed by a falling top-only support.
const CODES := ["o20"]
const SOLID := 2
const S := preload("res://src/sim/units.gd").SCALE
const Collision = preload("res://src/sim/collision.gd")
const Moves = preload("res://src/sim/moves.gd")
const Screen = preload("res://src/sim/screen.gd")
# Age tags: 0 idle, 1..72 arming, 73..125 falling (animation stops at 125).
const FIELDS := [["age", 0], ["home_y", 0], ["respawns", 0]]
const BOX := [-16 * S, -16 * S, 16 * S, 16 * S]
## The constant bounds, for the entity grid (EntityGrid files rows by it).
const GRID_BOUNDS := {"o20": BOX}


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form < 0 or form != floor(form):
		return {"ok": false, "error": "Invalid falling span form"}
	if form > 1:
		return {"ok": false, "degrade": true, "error": "falling span form F=%d" % form}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"home_y": int(source.y), "respawns": int(source.get("variant", 0) == 1)}


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if entity.age == 0:
		return
	entity.age = mini(125, entity.age + 1)
	if entity.age >= 73:
		if Collision.prepare(entity, world, BOX):
			Collision.vertical(
				entity, world, BOX, entity.vy, Collision.floor_at(entity, world, BOX)
			)
		entity.vy = mini(192 * 60, entity.vy + 256)
	if entity.y <= Screen.centre_y(state, world) + 832 * S:
		return
	if entity.respawns:
		entity.age = 0
		entity.y = entity.home_y
		entity.vy = 0
	else:
		entity.status = 3


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.age >= 73:
		return
	var box := Moves.player_box(state)
	var top: int = entity.y - 16 * S
	var standing: bool = (
		state.on_floor
		and state.x + box[2] >= entity.x - 16 * S
		and state.x + box[0] <= entity.x + 16 * S
		and state.y + box[3] <= top
		and state.y + box[3] + 2 * S >= top
	)
	if standing and entity.age == 0:
		entity.age = 1
	elif not standing:
		entity.age = 0


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - 16 * S, entity.y - 16 * S, entity.x + 16 * S, entity.y - 14 * S]


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var frame := 0
	if entity.age > 1:
		var units: int = (entity.age - 1) * 32
		if units >= 66 * 60:
			frame = 4
		elif units >= 18 * 60:
			frame = 1 + (units / 60 - 18) % 4
	return {
		"visible": entity.status == 1,
		"animation": "Idle" if entity.age == 0 else "Falling",
		"frame": frame
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.age >= 0
		and entity.age <= 125
		and entity.respawns in [0, 1]
		and entity.vy >= 0
		and entity.vy <= 192 * 60
	)
