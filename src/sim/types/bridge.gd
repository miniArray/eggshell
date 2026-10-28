extends RefCounted

const CODES := ["p1"]
const FIELDS := []
const STEP_PHASE := -1
const CONTACT_PHASE := -1


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func valid(_entity: Dictionary) -> bool:
	return true
