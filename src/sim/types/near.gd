extends RefCounted
## Neighbour queries for object types. Uses the registry index when it exists; otherwise
## every entity, in entity order. Callers still apply their own exact overlap tests.


static func query(state: Dictionary, world: Dictionary, box: Array) -> Array:
	var registry: Script = load("res://src/sim/registry.gd")
	if registry.has_method("nearby"):
		return registry.nearby(state, world, box)
	return state.entities
