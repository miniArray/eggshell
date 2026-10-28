extends RefCounted

const Life = preload("res://src/sim/life.gd")
const CODES := ["o5"]
const FIELDS := []
const STEP_PHASE := -1
const CONTACT_PHASE := 2
const Units = preload("res://src/sim/units.gd")
const S := Units.SCALE


static func create(_source: Dictionary, _world: Dictionary) -> Dictionary:
	return {}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if (
		state.x + 12 * S > entity.x - 8 * S
		and state.x - 12 * S < entity.x + 8 * S
		and state.y > entity.y - 8 * S
		and state.y - 56 * S < entity.y + 8 * S
	):
		Life.touch_goal(state, entity)


static func valid(_entity: Dictionary) -> bool:
	return true
