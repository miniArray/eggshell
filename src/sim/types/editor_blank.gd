extends RefCounted
## An editor-only blank placement. Play creates nothing for it: no body, no
## contact and nothing drawn. Its options are kept but never read.
## An empty code behaves the same: the loader cannot select an object for an empty
## name, so the placement keeps the blank editor form and spawns nothing.

const CODES := ["empty", ""]
const FIELDS := []
const STEP_PHASE := -1
const CONTACT_PHASE := -1


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func view_state(_entity: Dictionary, _state: Dictionary) -> Dictionary:
	return {"visible": false}


static func valid(_entity: Dictionary) -> bool:
	return true
