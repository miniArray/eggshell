extends SceneTree
## The entity grid behind Registry.nearby answers exactly what a scan of the table answers,
## in entity order, while entities move, grow, join, leave and dispatch. Invented entities
## and types only; no levels, scenes or assets.

const EntityGrid = preload("res://src/sim/entity_grid.gd")
const Registry = preload("res://src/sim/registry.gd")
const S := 3600
var checks := 0
var failures := 0
var seed := 4242
var next_token := 1


## Bounds read a saved field, as many real types do.
class Sized:
	extends RefCounted

	static func bounds(entity: Dictionary) -> Array:
		return [-entity.half, -entity.half * 2, entity.half, entity.half]


## Corners in either order: the grid must file both orders.
class Flipped:
	extends RefCounted

	static func bounds(entity: Dictionary) -> Array:
		return [entity.half, entity.half, -entity.half, -entity.half]


## No bounds: the entity is its position.
class Point:
	extends RefCounted


func _initialize() -> void:
	# Answer from the grid from the first query, so every check exercises it.
	EntityGrid.min_queries = 0
	random_checks()
	order_and_edge_checks()
	registry_checks()
	# The default switches between grid and scan by query count; answers stay equal.
	EntityGrid.min_queries = 4
	registry_checks()
	print("ENTITY_GRID_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func types() -> Dictionary:
	return {"sized": Sized, "flipped": Flipped}


func rand(limit: int) -> int:
	seed = (seed * 1103515245 + 12345) % 2147483648
	# The low bits of this generator repeat quickly; use the high ones.
	return (seed >> 16) % limit


func make_entity() -> Dictionary:
	var code: String = ["sized", "sized", "flipped", "point"][rand(4)]
	var entity := {
		"code": code,
		"token": next_token,
		"x": (rand(6000) - 1000) * S,
		"y": (rand(2000) - 500) * S,
		"half": (4 + rand(60)) * S,
	}
	next_token += 1
	if rand(40) == 0:
		# Wider than the per-row cell limit: kept in the list every query reads.
		entity.half = 40000 * S
	return entity


## The scan the grid must equal, written out independently: bounds around the position
## touch the inclusive box; an entity without bounds is its position.
func scan(state: Dictionary, box: Array) -> Array:
	var result := []
	for entity: Dictionary in state.entities:
		var type: Script = types().get(entity.code, Point)
		var b: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
		if (
			entity.x + b[2] >= box[0]
			and entity.x + b[0] <= box[2]
			and entity.y + b[3] >= box[1]
			and entity.y + b[1] <= box[3]
		):
			result.append(entity)
	return result


func probe() -> Array:
	var x := (rand(6400) - 1200) * S
	var y := (rand(2400) - 700) * S
	var size := rand(10)
	var w := (1 + rand(96 if size else 2000)) * S
	var h := (1 + rand(96 if size else 1000)) * S
	return [x, y, x + w, y + h]


func query(state: Dictionary, world: Dictionary, box: Array) -> Array:
	var found: Variant = EntityGrid.query(state, world, box, types(), Point)
	return scan(state, box) if found == null else found


func same(found: Array, expected: Array) -> bool:
	if found.size() != expected.size():
		return false
	for index in found.size():
		if not is_same(found[index], expected[index]):
			return false
	return true


func compare(state: Dictionary, world: Dictionary, label: String) -> void:
	var box := probe()
	check(same(query(state, world, box), scan(state, box)), "%s: %s" % [label, box])


## A probe at an entity that just moved, where a stale filing would miss it.
func compare_at(state: Dictionary, world: Dictionary, entity: Dictionary, label: String) -> void:
	var box := [entity.x - 2 * S, entity.y - 2 * S, entity.x + 2 * S, entity.y + 2 * S]
	var found := query(state, world, box)
	# A flipped box only counts when the probe holds it whole, so it may be absent here.
	var present: bool = (
		entity.code == "flipped"
		or found.any(func(other: Dictionary) -> bool: return is_same(other, entity))
	)
	check(present and same(found, scan(state, box)), "%s: %s" % [label, box])


func random_checks() -> void:
	var state := {"entities": []}
	var world := {}
	for index in 300:
		state.entities.append(make_entity())
	EntityGrid.attach(state, world)
	for round in 400:
		var grid := EntityGrid.attach(state, world)
		match rand(8):
			0, 1:
				# A dispatch that moves and resizes its entity and queries midway.
				var entity: Dictionary = state.entities[rand(state.entities.size())]
				EntityGrid.begin(grid, entity)
				entity.x += (rand(801) - 400) * S
				entity.half = (4 + rand(80)) * S
				compare(state, world, "During a dispatch")
				compare_at(state, world, entity, "At the dispatched entity")
				entity.y += (rand(801) - 400) * S
				compare_at(state, world, entity, "Later in the same dispatch")
				EntityGrid.end(grid, entity)
				compare_at(state, world, entity, "After a dispatch")
			2:
				# Another entity's code moves it and reports the change.
				var other: Dictionary = state.entities[rand(state.entities.size())]
				other.x = (rand(6000) - 1000) * S
				other.half = (4 + rand(200)) * S
				EntityGrid.touch(world, other)
				compare_at(state, world, other, "After a reported change")
			3:
				for count in 1 + rand(3):
					state.entities.append(make_entity())
			4:
				# Compaction keeps order and drops some entities, in a new array.
				var kept := []
				for entity: Dictionary in state.entities:
					if rand(10):
						kept.append(entity)
				state.entities = kept
			5:
				if rand(20) == 0:
					# A replaced table with the same tokens: everything is filed again.
					var fresh := []
					for entity: Dictionary in state.entities:
						fresh.append(entity.duplicate())
					state.entities = fresh
			_:
				pass
		for count in 3:
			compare(state, world, "Round %d" % round)
	# A new play state never reuses the old state's grid.
	var other_state := {"entities": [make_entity()]}
	var box: Array = [-100000 * S, -100000 * S, 100000 * S, 100000 * S]
	check(
		EntityGrid.query(other_state, world, box, types(), Point) == null,
		"Another state is not answered from this grid"
	)


func order_and_edge_checks() -> void:
	var state := {"entities": []}
	var world := {}
	# Same place, many entities: results follow table order, not filing order.
	for index in 20:
		state.entities.append(
			{"code": "sized", "token": index + 1, "x": 100 * S, "y": 100 * S, "half": 8 * S}
		)
	EntityGrid.attach(state, world)
	var box := [96 * S, 96 * S, 104 * S, 104 * S]
	check(same(query(state, world, box), state.entities), "Table order")
	# Touching edges count, as in the scan.
	var edge := {"code": "point", "token": 99, "x": 600 * S, "y": 600 * S}
	state.entities.append(edge)
	var touching := query(state, world, [600 * S, 590 * S, 610 * S, 600 * S])
	check(touching.size() == 1 and is_same(touching[0], edge), "Point on the edge")
	# Negative coordinates file in the right cells.
	var negative := {"code": "sized", "token": 100, "x": -1 * S, "y": -1 * S, "half": S / 2}
	state.entities.append(negative)
	var near_zero := query(state, world, [-S, -S, -S / 2, -S / 2])
	check(near_zero.has(negative), "Cell edges below zero")
	# Inverted or huge probes fall back to the scan.
	check(EntityGrid.query(state, world, [10, 10, 0, 0], types(), Point) == null, "Inverted")
	check(
		EntityGrid.query(state, world, [0, 0, 5000 * S, 5000 * S], types(), Point) == null,
		"Huge probe"
	)
	# A repeated token makes dispatch marks ambiguous: the grid refuses to answer.
	var twin := {"code": "point", "token": 1, "x": 0, "y": 0}
	state.entities.append(twin)
	check(EntityGrid.query(state, world, box, types(), Point) == null, "Repeated token")


## Registry.nearby with the grid attached equals its scan for real types and placeholders.
func registry_checks() -> void:
	var state := {"entities": []}
	var world := {}
	var codes := ["o28", "neutral_unknown", "o12", "o32"]
	for index in 200:
		state.entities.append(
			{
				"code": codes[index % codes.size()],
				"token": index + 1,
				"x": rand(3000) * S,
				"y": rand(800) * S,
				"status": 1
			}
		)
	for round in 60:
		# One step: a varying number of queries, so the default switches modes.
		var grid := EntityGrid.attach(state, world)
		for query_index in rand(8):
			var box := probe()
			check(
				same(Registry.nearby(state, world, box), registry_scan(state, box)),
				"Registry nearby equals a scan: %s" % [box]
			)
			var entity: Dictionary = state.entities[rand(state.entities.size())]
			EntityGrid.begin(grid, entity)
			entity.x += (rand(401) - 200) * S
			EntityGrid.end(grid, entity)
			check(
				Registry.nearby(state, world, [entity.x, entity.y, entity.x, entity.y]).has(entity),
				"A moved entity is found where it is"
			)


func registry_scan(state: Dictionary, box: Array) -> Array:
	var result := []
	for entity: Dictionary in state.entities:
		var type := Registry.lookup(entity.code)
		var b: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
		if (
			entity.x + b[2] >= box[0]
			and entity.x + b[0] <= box[2]
			and entity.y + b[3] >= box[1]
			and entity.y + b[1] <= box[3]
		):
			result.append(entity)
	return result


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
