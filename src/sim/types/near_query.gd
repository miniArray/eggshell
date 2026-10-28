extends RefCounted
## Shared neighbour queries for object types, answered by `Registry.nearby` in entity order.
## Callers still apply their own exact overlap tests.

const Collision = preload("res://src/sim/collision.gd")
static var _registry: Script = null


## The registry, resolved after type loading to avoid a registry/type import cycle.
static func registry() -> Script:
	if _registry == null:
		_registry = load("res://src/sim/registry.gd")
	return _registry


static func nearby(state: Dictionary, world: Dictionary, box: Array) -> Array:
	return registry().nearby(state, world, box)


## Strike every active, visible entity with a hit hook inside a world-space box.
static func strike(
	state: Dictionary, world: Dictionary, box: Array, kind: int, from_x: int, skip_token: int
) -> void:
	var dispatch := registry()
	for other: Dictionary in nearby(state, world, box):
		var type: Script = dispatch.lookup(other.code)
		if (
			other.token == skip_token
			or other.status != 1
			or other.get("held", 0) == 1
			or other.get("hidden", 0) == 1
			or not type.has_method("hit")
		):
			continue
		if dispatch.overlaps_box(other, type, box):
			type.hit(other, state, world, kind, from_x)


## Refile another entity's solid boxes after this code moved or enlarged them.
## The solid index refiles the dispatched entity itself.
static func refresh_solid(world: Dictionary, entity: Dictionary) -> void:
	Collision.refresh(world, entity)
