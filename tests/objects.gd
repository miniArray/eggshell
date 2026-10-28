extends SceneTree

const Fixtures = preload("res://tests/fixtures.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const World = preload("res://src/sim/world.gd")
const Save = preload("res://src/save/snapshot.gd")
const S := State.SCALE
var failures := 0
var assertions := 0


func _initialize() -> void:
	var world := Fixtures.world("bounce")
	world.goals.clear()
	check(world.springs.size() == 1, "Pad record compiles")
	for held: bool in [false, true]:
		var state := State.create(world)
		state.x = 384 * S
		state.y = 353 * S
		state.vy = 200 * 60
		Sim.advance(state, Sim.JUMP if held else 0, world)
		check(state.vy == (-1216 if held else -384) * 60, "Pad contact impulse")
		check(state.springs[0].squash == 12, "Squash lasts twelve ticks")
		var saved := Save.decode(Save.encode(state), world.identity)
		check(saved.ok and saved.state == state, "Pad state restores exactly")
	var below := State.create(world)
	below.x = 960 * S
	below.y = 320 * S
	below.vy = -776 * 60
	for tick in 8:
		Sim.advance(below, Sim.JUMP, world)
	check(below.y < 256 * S and below.support_bridge == 0, "Bridge passes upward movement")
	var landing := State.create(world)
	landing.x = 960 * S
	landing.y = 255 * S
	landing.vy = 200 * 60
	Sim.advance(landing, 0, world)
	check(
		landing.y < 256 * S and 256 * S - landing.y <= S / 16 and landing.support_bridge == 1,
		"Bridge supports falling feet outside the closed surface"
	)
	world = Fixtures.world("lagoon")
	world.goals.clear()
	check(World.water_at(world, 1280 * S, 364 * S), "Pool has water")
	var swimming := State.create(world)
	swimming.x = 1280 * S
	swimming.y = 375 * S
	for tick in 60:
		Sim.advance(swimming, Sim.RIGHT, world)
	check(swimming.swimming == 1 and swimming.deaths == 0, "Buoyancy activates")
	check(swimming.vx == 200 * 60, "Swimming speed cap")
	var copy := Save.decode(Save.encode(swimming), world.identity)
	check(copy.ok, "Water checkpoint decodes")
	for tick in 120:
		Sim.advance(swimming, Sim.JUMP | Sim.RIGHT, world)
		Sim.advance(copy.state, Sim.JUMP | Sim.RIGHT, world)
	check(Save.encode(swimming) == Save.encode(copy.state), "Restored swim future matches")
	print("OBJECT_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
