extends RefCounted
## The lifetime module owns contact checks, awards and checkpoint phases.

const Life = preload("res://src/sim/life.gd")
const CODES := ["o6"]
const FIELDS := [["respawn_x", 0], ["respawn_y", 0], ["health_bonus", 10]]
const STEP_PHASE := -1
const CONTACT_PHASE := 2


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"respawn_x": int(source.respawn_x), "respawn_y": int(source.respawn_y),
		"health_bonus": 30 if source.get("variant", 0) == 1 else 10}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	Life.touch_checkpoint(state, entity)


static func valid(entity: Dictionary) -> bool:
	return entity.health_bonus in [10, 30]
