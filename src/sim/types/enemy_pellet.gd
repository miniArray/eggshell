extends RefCounted
## A straight, terrain-independent shot. It cannot be eaten or stomped.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["enemy_pellet"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := false
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const FIELDS := Body.FIELDS


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	var values := Body.create(source)
	values.vx = values.facing * 256 * 60
	return values


static func bounds(_entity: Dictionary) -> Array:
	return [-8 * S, -4 * S, 8 * S, 4 * S]


static func step(entity: Dictionary, state: Dictionary, _world: Dictionary) -> void:
	if Body.process(entity, state) == Body.GONE:
		return
	entity.vx = entity.facing * 256 * 60
	entity.x += entity.vx


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if Body.player_overlap(entity, state, bounds(entity)):
		Body.hurt(entity, state)


static func projectile_contact(
	_entity: Dictionary, _projectile: Dictionary, _state: Dictionary, _world: Dictionary
) -> int:
	return 0


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3]


static func valid(entity: Dictionary) -> bool:
	return (
		Body.valid(entity)
		and entity.variant == 0
		and entity.held == 0
		and entity.spat == 0
		and entity.vy == 0
	)
