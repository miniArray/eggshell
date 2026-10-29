extends RefCounted
## A full solid hazard. Player contact is fatal; a thrown egg breaks it.

const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o12"]
const SOLID := 1
const STEP_PHASE := -1
const FIELDS := [["form", 0]]
const HALF := 16 * S
## The constant bounds, for the entity grid (EntityGrid files rows by it).
const GRID_BOUNDS := {"o12": [-HALF, -HALF, HALF, HALF]}
# Ceiling probes reach 2 px above the head; other sides count from 1 px.
const REACH_TOP := 2 * S
const REACH := S


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form != floor(form):
		return {"ok": false, "error": "Invalid thorn form"}
	if form < 0 or form > 1:
		return {"ok": false, "degrade": true, "error": "Unsupported thorn form"}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"form": int(source.get("variant", 0))}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(_entity: Dictionary) -> Array:
	return [-HALF, -HALF, HALF, HALF]


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x - HALF, entity.y - HALF, entity.x + HALF, entity.y + HALF]


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if entity.status != 1 or state.get("captured_by", 0):
		return
	var box := Moves.player_box(state)
	if (
		state.x + box[2] + REACH > entity.x - HALF
		and state.x + box[0] - REACH < entity.x + HALF
		and state.y + box[3] + REACH > entity.y - HALF
		and state.y + box[1] - REACH_TOP < entity.y + HALF
	):
		Life.kill(state, Life.HAZARD)


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind == Hits.EGG and entity.status == 1:
		entity.status = 3


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.status != 1:
		return 0
	hit(entity, state, world, Hits.EGG, projectile.get("x", entity.x))
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "animation": "Default", "frame": entity.form}


static func valid(entity: Dictionary) -> bool:
	return entity.form in [0, 1]
