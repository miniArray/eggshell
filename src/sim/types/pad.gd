extends RefCounted

const Behavior = preload("res://src/sim/bounce_pad.gd")
const CODES := ["o11"]
const FIELDS := [["squash", 0], ["active", 1], ["large", 0], ["single_use", 0]]
const STEP_PHASE := 1
const CONTACT_PHASE := 0


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"large": int(source.large), "single_use": int(source.single_use)}


static func step(entity: Dictionary, _state: Dictionary, world: Dictionary) -> void:
	Behavior.advance_entity(entity, world)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, input: int) -> void:
	Behavior.contact_entity(entity, state, input)


static func valid(entity: Dictionary) -> bool:
	return (
		entity.vx == 0
		and entity.vy >= 0
		and entity.vy <= 704 * 60
		and entity.squash >= 0
		and entity.squash <= 12
		and entity.active in [0, 1]
		and entity.large in [0, 1]
		and entity.single_use in [0, 1]
	)
