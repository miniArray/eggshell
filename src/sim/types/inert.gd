extends RefCounted
## Placeholder for an unregistered code or a form a type does not build yet.
## It keeps identity, position and all immutable placement options, and never acts.

const CODES := []
const FIELDS := []
const STEP_PHASE := -1
const CONTACT_PHASE := -1


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func valid(_entity: Dictionary) -> bool:
	return true
