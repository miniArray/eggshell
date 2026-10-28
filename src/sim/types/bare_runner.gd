extends RefCounted
## Placed shell-less walkers. They share the released runner's body and rules.

const Walker = preload("res://src/sim/types/shell_walker.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Options = preload("res://src/sim/enemy_options.gd")
const Hits = preload("res://src/sim/hits.gd")
const CODES := ["e7", "e9"]
const ENEMY := true
const ELEMENT_REACTIONS := Walker.ELEMENT_REACTIONS
const DYNAMIC := true
const GOAL_COIN := true
const HIT_KIND := Hits.SHELL
const STEP_PHASE := 0
const CONTACT_PHASE := 1
const FIELDS := Walker.FIELDS


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	return Options.prepare(source, 0)


static func create(source: Dictionary, world: Dictionary) -> Dictionary:
	var values := Walker.create(source, world)
	values.colour = 1 if source.code == "e9" else 0
	values.mode = Walker.BARE
	values.inside = 0
	return values


static func bounds(entity: Dictionary) -> Array:
	return Walker.bounds(entity)


static func step(entity: Dictionary, state: Dictionary, world: Dictionary) -> void:
	Walker.step(entity, state, world)


static func contact(entity: Dictionary, state: Dictionary, world: Dictionary, input: int) -> void:
	Walker.contact(entity, state, world, input)


static func tongue(entity: Dictionary, state: Dictionary, world: Dictionary) -> int:
	return Walker.tongue(entity, state, world)


static func hit(
	entity: Dictionary, state: Dictionary, world: Dictionary, kind: int, from_x: int
) -> void:
	Walker.hit(entity, state, world, kind, from_x)


static func projectile_contact(
	entity: Dictionary, projectile: Dictionary, state: Dictionary, world: Dictionary
) -> int:
	return Walker.projectile_contact(entity, projectile, state, world)


static func on_remove(entity: Dictionary, state: Dictionary) -> void:
	Walker.on_remove(entity, state)


static func view_state(entity: Dictionary, state: Dictionary) -> Dictionary:
	return Walker.view_state(entity, state)


static func finished(entity: Dictionary) -> bool:
	return Walker.finished(entity)


static func valid(entity: Dictionary) -> bool:
	return (
		Walker.valid(entity)
		and entity.variant == 0
		and entity.inside == 0
		and entity.mode in [Walker.BARE, Walker.BARE_TURN, Walker.ENTER, Walker.SLIDE]
	)
