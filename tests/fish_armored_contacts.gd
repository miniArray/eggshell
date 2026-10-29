extends SceneTree
## Invented placements exercise motion, contact and restored futures through the simulation.

const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Collision = preload("res://src/sim/collision.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Grid = preload("res://src/sim/entity_grid.gd")
const S := State.SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	fish_air_motion()
	burst_armor(false)
	burst_armor(true)
	print("FISH_ARMORED_CONTACTS_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func fixture(objects: Dictionary) -> Dictionary:
	var world := {
		"identity": "invented fish and armor contacts".sha256_text(),
		"spawn_x": 64 * S,
		"spawn_y": 300 * S,
		"spawn_facing": 1,
		"map_index": 1,
		"initial_map": 1,
		"map_count": 1,
		"flowers_target": 0,
		"redcoins_target": 0,
		"width": 4096 * S,
		"height": 1024 * S,
		"layers": []
	}
	check(Registry.compile_map(objects, world).ok, "Invented placements compile")
	world.maps = {1: world.duplicate()}
	var state := State.create(world)
	Registry.spawn_map(state, world)
	for entity: Dictionary in state.entities:
		entity.status = Registry.ACTIVE
		if entity.has("started"):
			entity.started = 1
	return {"world": world, "state": state}


func by_id(state: Dictionary, id: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.id == id:
			return entity
	return {}


func fish_air_motion() -> void:
	var unit := fixture({"fish": {"A": "e20", "X": 700, "Y": 180, "F": 2}})
	var fish := by_id(unit.state, "fish")
	fish.mode = 4
	fish.vx = -128 * 60
	fish.vy = -800 * 60
	var y: int = fish.y
	Sim.advance(unit.state, 0, unit.world)
	check(fish.vy == -800 * 60 + 2048, "An airborne fish gains one tick of dry gravity")
	check(
		fish.y == y - 800 * 60 + 1024,
		"An airborne fish moves by the mean of its old and new vertical speed"
	)
	restored_future(unit)


func burst_armor(armor_first: bool) -> void:
	var armor_id := "a" if armor_first else "z"
	var objects := {}
	var armor_source := {"A": "e11", "X": 480, "Y": 284, "F": 3}
	if armor_first:
		objects[armor_id] = armor_source
	objects["burst"] = {"A": "e23", "X": 400, "Y": 284}
	if not armor_first:
		objects[armor_id] = armor_source
	objects["floor"] = {"A": "p2", "X": 500, "Y": 316, "E1": "1024"}
	var unit := fixture(objects)
	var soft := by_id(unit.state, "burst")
	var armor := by_id(unit.state, armor_id)
	check(
		(unit.state.entities.find(armor) < unit.state.entities.find(soft)) == armor_first,
		"The fixture really reverses the armor and burst dispatch order"
	)
	var type: Script = Registry.lookup("e23")
	soft.mode = type.SQUASH
	soft.timer = 1
	var x: int = armor.x
	Grid.min_queries = 0
	Collision.begin_step(unit.state, unit.world, Registry)
	Registry.nearby(unit.state, unit.world, [464 * S, 268 * S, 496 * S, 300 * S])
	Sim.advance(unit.state, 0, unit.world)
	check(soft.status == Registry.DEFEATED, "The soft body bursts")
	check(armor.vx == 448 * 60, "The burst reaches nearby armor, in either dispatch order")
	check(armor.x == x, "Burst knockback starts after this tick's body motion")
	check(armor.vy < 0, "Standing armor hops when knocked away")
	Sim.advance(unit.state, 0, unit.world)
	check(armor.x > x, "Knocked armor moves away instead of remaining in the player's path")
	restored_future(unit)
	Grid.min_queries = 4


func restored_future(unit: Dictionary) -> void:
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "The changed actor state has a valid snapshot")
	var decoded := Snapshot.decode(bytes, unit.state.identity, unit.world)
	check(decoded.ok, "The changed actor state restores")
	if not decoded.ok:
		return
	var restored: Dictionary = decoded.state
	var world: Dictionary = unit.world.duplicate(true)
	for _tick in 120:
		Sim.advance(unit.state, 0, unit.world)
		Sim.advance(restored, 0, world)
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(restored),
		"Restoring midway through actor motion preserves its full future"
	)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
