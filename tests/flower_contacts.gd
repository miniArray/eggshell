extends SceneTree
## Synthetic picture-width activation and the resulting upward contact.

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Sim = preload("res://src/sim/step.gd")
const Save = preload("res://src/save/snapshot.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const S := State.SCALE
var assertions := 0
var failures := 0


func _initialize() -> void:
	for variant in [0, 1]:
		for facing in [-1, 1]:
			picture_contact(variant, facing)
	print("FLOWER_CONTACT_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func course(variant: int) -> Dictionary:
	var world := Fixtures.world()
	world.layers = []
	world.bridges = []
	world.width = 4000 * S
	world.height = 2000 * S
	world.spawn_x = 200 * S
	world.spawn_y = 512 * S
	var built := World.setup_objects(
		{"objects": {"flower": {"A": "e3", "X": 1000, "Y": 512, "F": variant}}}, world
	)
	check(built.ok, "Synthetic flower compiles")
	world.maps = {1: world.duplicate()}
	return world


func picture_contact(variant: int, facing: int) -> void:
	var world := course(variant)
	var state := State.create(world)
	var flower: Dictionary = state.entities[0]
	flower.facing = facing
	state.x = flower.x + facing * 266 * S / 10
	state.y = flower.y - 312 * S / 10
	# The picture enters the reference screen while the narrower contact body is outside.
	state.camera_x = flower.x - (416 + (24 if facing < 0 else 16) - 1) * S
	Registry.advance(state, world, 0)
	check(flower.status == 1, "Flower wakes by picture width in either facing and variant")
	check(flower.x == 1000 * S, "Waking does not move the flower")
	var restored := Save.decode(Save.encode(state), world.identity)
	check(restored.ok, "A just-activated flower restores")
	if not restored.ok:
		return
	for player: Dictionary in [state, restored.state]:
		Registry.contact(player, Sim.JUMP, world)
		var body: Dictionary = player.entities[0]
		check(body.status == 1, "The player is initially outside the contact body")
		Registry.advance(player, world, 0)
		check(body.x == 1000 * S + facing * 48 * 60, "Flower starts walking on the next tick")
		player.y = body.y - 312 * S / 10
		player.vy = -640 * 60
		var bounce: int = -absi(body.vy / 2) - 704 * 60
		Registry.contact(player, Sim.JUMP, world)
		check(
			body.status == 3 and player.vy == bounce,
			"Earlier activation catches the upward contact and defeats the flower"
		)
		player.y = body.y - 33 * S
		player.vy = 75 * 60
		Registry.contact(player, Sim.JUMP, world)
		check(player.vy == 75 * 60, "The defeated flower cannot cause a later falling bounce")
	check(
		Save.encode(state) == Save.encode(restored.state), "Restored contact future is byte exact"
	)


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
