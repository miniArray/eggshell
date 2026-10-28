extends RefCounted
## A full volume whose paired forms encode intact and cracked states.
const CODES := ["o28"]
const SOLID := 1
const S := preload("res://src/sim/units.gd").SCALE
const FIELDS := [["form", 0]]
const BOX := [-32 * S, -32 * S, 32 * S, 32 * S]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var form: Variant = source.properties.get("F", 0)
	if not (form is int or form is float) or not is_finite(form) or form != floor(form) or form < 0:
		return {"ok": false, "error": "Invalid hard block form"}
	if form > 17:
		return {"ok": false, "degrade": true, "error": "hard block form F=%d" % form}
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
	return [entity.x - 32 * S, entity.y - 32 * S, entity.x + 32 * S, entity.y + 32 * S]


static func hit(
	entity: Dictionary, _state: Dictionary, _world: Dictionary, kind: int, _from_x: int
) -> void:
	if kind != 1 or entity.status != 1:
		return
	if entity.form % 2 == 0:
		entity.form += 1
	else:
		entity.status = 3


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	if entity.status != 1:
		return 0
	# The following physical bounce spends this extra charge, preserving the budget.
	if projectile.bounces < 0x7fffffffffffffff:
		projectile.bounces += 1
	hit(entity, state, world, 1, projectile.get("x", entity.x))
	return 3


static func tongue(entity: Dictionary, _state: Dictionary, _world: Dictionary) -> int:
	return 2 if entity.status == 1 else 0


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": entity.status == 1, "animation": "Rock", "frame": entity.form}


static func valid(entity: Dictionary) -> bool:
	return entity.form >= 0 and entity.form <= 17
