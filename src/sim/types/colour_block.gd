extends RefCounted
## A wide full solid that changes colour on each egg hit and breaks after its last colour.

const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["o29"]
const SOLID := 1
const STEP_PHASE := -1
const LAST_FORM := 2
const FIELDS := [["form", 0]]
const BOX := [-32 * S, -16 * S, 32 * S, 16 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form != floor(form):
		return {"ok": false, "error": "Invalid colour block form"}
	if form < 0 or form > LAST_FORM:
		return {"ok": false, "degrade": true, "error": "Unsupported colour block form"}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"form": int(source.get("variant", 0))}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func bounds(_entity: Dictionary) -> Array:
	return BOX


static func solid_box(entity: Dictionary) -> Array:
	if entity.status != 1:
		return []
	return [entity.x + BOX[0], entity.y + BOX[1], entity.x + BOX[2], entity.y + BOX[3]]


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind != Hits.EGG or entity.status != 1:
		return
	if entity.form < LAST_FORM:
		entity.form += 1
	else:
		entity.status = 3


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.status != 1:
		return 0
	# The block refunds the hit that its own bounce spends.
	if projectile.get("bounces", 0) < 0x7fffffffffffffff:
		projectile.bounces = int(projectile.get("bounces", 0)) + 1
	hit(entity, state, world, Hits.EGG, projectile.get("x", entity.x))
	return 3


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "animation": "Color", "frame": entity.form}


static func valid(entity: Dictionary) -> bool:
	return entity.form >= 0 and entity.form <= LAST_FORM
