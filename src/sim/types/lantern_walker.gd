extends RefCounted
## The lantern-carrying form of the small walker. It behaves exactly like the plain walker;
## only its look and the light it carries differ. Hooks run the shared walker rules under
## the plain walker's code and restore this code before returning.

const Actor = preload("res://src/sim/types/actor.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const CODES := ["e32"]
const ENEMY := true
const DYNAMIC := true
const GOAL_COIN := true
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const BASE := "e1"
const LAST_FORM := 3
const FIRST_LOOK := 5
const FIELDS := Actor.FIELDS


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, LAST_FORM)


static func create(source: Dictionary, world: Dictionary) -> Dictionary:
	return Actor.create(source, world)


static func bounds(entity: Dictionary) -> Array:
	return Motion.box(entity, BASE)


static func activation_bounds(entity: Dictionary) -> Array:
	return _as_base(entity, func() -> Variant: return Actor.activation_bounds(entity))


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	_as_base(entity, func() -> void: Actor.step(entity, state, world))


static func activate(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	_as_base(entity, func() -> void: Actor.activate(entity, state, world))


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	_as_base(entity, func() -> void: Actor.contact(entity, state, world, input))


static func tongue(entity: Dictionary, state: Dictionary, world: Dictionary) -> int:
	return _as_base(entity, func() -> Variant: return Actor.tongue(entity, state, world))


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	_as_base(entity, func() -> void: Actor.hit(entity, state, world, kind, from_x))


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	return _as_base(
		entity, func() -> Variant: return Actor.projectile_contact(entity, projectile, state, world)
	)


static func _as_base(entity: Dictionary, call: Callable) -> Variant:
	var code: String = entity.code
	entity.code = BASE
	var result: Variant = call.call()
	entity.code = code
	return result


static func view_state(entity: Dictionary, _state: Dictionary) -> Dictionary:
	var pose := "Idle" if entity.mode == 0 else "Walk"
	return {
		"visible": entity.held == 0 and entity.hidden == 0,
		"animation": "Roll" if entity.roll else str(entity.variant + FIRST_LOOK) + pose
	}


static func valid(entity: Dictionary) -> bool:
	return (
		entity.variant <= LAST_FORM
		and _as_base(entity, func() -> Variant: return Actor.valid(entity))
	)
