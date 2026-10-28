extends RefCounted
## Saved entry-contact memory for persistent weapons and immune targets.

const Body = preload("res://src/sim/enemy_body.gd")
const CODES := ["enemy_overlap"]
const DYNAMIC := true
const FIELDS := [["a", 0], ["b", 0]]


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var raw: Dictionary = source.get("properties", {})
	for key: String in ["a", "b"]:
		if not raw.get(key) is int or raw[key] <= 0:
			return {"ok": false, "error": "Invalid contact token"}
	return {"ok": true}


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"a": int(source.properties.a), "b": int(source.properties.b), "status": 1}


static func bounds(_entity: Dictionary) -> Array:
	return [0, 0, 0, 0]


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	var registry: Script = Body.registry_for()
	var a: Dictionary = registry.find_token(state, entity.a)
	var b: Dictionary = registry.find_token(state, entity.b)
	if (
		a.is_empty()
		or b.is_empty()
		or a.status != 1
		or b.status != 1
		or a.get("held", 0)
		or b.get("held", 0)
		or a.get("hidden", 0)
		or b.get("hidden", 0)
	):
		entity.status = 3
		return
	var type_a: Script = registry.lookup(a.code)
	var type_b: Script = registry.lookup(b.code)
	if not Body.overlap(Body.world_box(a, type_a.bounds(a)), Body.world_box(b, type_b.bounds(b))):
		entity.status = 3


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func view_state(_entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": false}


static func finished(entity: Dictionary) -> bool:
	return entity.status == 3


static func valid(entity: Dictionary) -> bool:
	return entity.a > 0 and entity.b > 0 and entity.a != entity.b
