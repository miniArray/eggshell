extends RefCounted
## A catchable ballistic shot. Landing or an impact destroys it.

const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Hits = preload("res://src/sim/hits.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["enemy_spike"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const FIELDS := Body.FIELDS


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Body.create(source)


static func bounds(_entity: Dictionary) -> Array:
	return [-12 * S, -12 * S, 12 * S, 12 * S]


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	if Body.process(entity, state) in [Body.HELD, Body.GONE]:
		return
	var box := bounds(entity)
	if Body.spit_step(entity, state, world, box) or Body.hazards(entity, state, world, box):
		return
	Motion.move(entity, world, box, entity.vx, true)
	if Motion.gravity_box(entity, world, box, 1536):
		Body.remove(entity, state)


static func contact(entity: Dictionary, state: Dictionary, _world: Dictionary, _input: int) -> void:
	if Body.player_overlap(entity, state, bounds(entity)):
		Body.hurt(entity, state)


static func tongue(entity: Dictionary, state: Dictionary, _world: Dictionary) -> int:
	return Body.tongue(entity, state)


static func hit(
	entity: Dictionary, state: Dictionary, _world: Dictionary, _kind: int, _from_x: int
) -> void:
	Body.remove(entity, state)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	var kind := Body.projectile_kind(projectile)
	if kind == Hits.EGG:
		projectile.fall_on_terrain = 1
	hit(entity, state, world, kind, projectile.x)
	return 3


static func finished(entity: Dictionary) -> bool:
	return entity.status in [2, 3] and entity.held == 0


static func valid(entity: Dictionary) -> bool:
	return Body.valid(entity) and entity.variant == 0
