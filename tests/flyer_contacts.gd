extends SceneTree
## Synthetic creation, activation and contact checks. No captured level data.

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Sim = preload("res://src/sim/step.gd")
const Save = preload("res://src/save/snapshot.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const S := State.SCALE
var assertions := 0
var failures := 0


func _initialize() -> void:
	creation_relative_wave()
	inactive_retreat()
	picture_activation()
	flight_frame_contacts()
	runtime_birth()
	print("FLYER_CONTACT_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func course(x: int) -> Dictionary:
	var world := Fixtures.world()
	world.layers = []
	world.bridges = []
	world.width = 4000 * S
	world.height = 2000 * S
	world.spawn_x = 200 * S
	world.spawn_y = 512 * S
	var built := World.setup_objects(
		{"objects": {"flyer": {"A": "e2", "X": x, "Y": 512, "M": 0, "F": 0}}}, world
	)
	check(built.ok, "Synthetic flyer compiles")
	world.maps = {1: world.duplicate()}
	return world


func creation_relative_wave() -> void:
	var world := course(1500)
	var state := State.create(world)
	var flyer: Dictionary = state.entities[0]
	check(flyer.status == 2, "Distant flyer is removed before its first activation")
	state.camera_x = 1000 * S
	Registry.advance(state, world, 0)
	check(flyer.status == 0 and flyer.timer == 0, "Returning anchor creates a new inactive wave")
	check(flyer.y == 512 * S, "Recreated flyer starts at its anchor")
	for tick in 45:
		state.frame += 1
		Registry.advance(state, world, 0)
	check(flyer.status == 0 and flyer.x == 1500 * S, "Inactive flyer has no horizontal swing")
	check(flyer.y == 524 * S, "Inactive wave reaches its crest 45 ticks after creation")
	var restored := Save.decode(Save.encode(state), world.identity)
	check(restored.ok, "Inactive wave snapshot decodes")
	state.camera_x = 1100 * S
	restored.state.camera_x = state.camera_x
	for tick in 100:
		state.frame += 1
		restored.state.frame += 1
		Registry.advance(state, world, 0)
		Registry.advance(restored.state, world, 0)
	check(flyer.status == 1, "Flyer activates after its wave has already started")
	check(
		Save.encode(state) == Save.encode(restored.state),
		"Delayed activation replays after restore"
	)
	# Despawn and return a second time: neither the level frame nor old swing survives.
	state.camera_x = 3000 * S
	Registry.advance(state, world, 0)
	state.camera_x = 1000 * S
	Registry.advance(state, world, 0)
	check(flyer.timer == 0 and flyer.phase == 0, "Recreation resets both independent motions")
	Registry.advance(state, world, 0)
	check(flyer.y == 512 * S + Motion.sine(1, 180, 12 * S), "New wave starts on the next tick")


func inactive_retreat() -> void:
	for recreated in [false, true]:
		var world := course(1500 if recreated else 1200)
		var state := State.create(world)
		var flyer: Dictionary = state.entities[0]
		if recreated:
			state.camera_x = 1000 * S
			Registry.advance(state, world, 0)
		check(flyer.status == 0, "Retreat starts with a created but never activated flyer")
		var age: int = flyer.timer
		state.camera_x = 3000 * S
		Registry.advance(state, world, 0)
		check(flyer.status == 0, "Retreat beyond despawn distance does not cull an inactive flyer")
		check(flyer.timer == (age + 1) % 180, "Inactive wave continues during retreat")
		var restored := Save.decode(Save.encode(state), world.identity)
		check(restored.ok, "Retreated inactive flyer restores")
		state.camera_x = 700 * S
		restored.state.camera_x = state.camera_x
		Registry.advance(state, world, 0)
		Registry.advance(restored.state, world, 0)
		check(flyer.status == 0, "Returning camera keeps the same inactive instance")
		check(
			(
				flyer.timer == (age + 2) % 180
				and flyer.y == 512 * S + Motion.sine((age + 2) % 180, 180, 12 * S)
			),
			"Return preserves the creation-relative wave rather than recreating it"
		)
		check(
			Save.encode(state) == Save.encode(restored.state),
			"Retreat and return replay after restore"
		)


func picture_activation() -> void:
	var world := course(1000)
	var state := State.create(world)
	var flyer: Dictionary = state.entities[0]
	state.camera_x = 568 * S
	Registry.advance(state, world, 0)
	check(flyer.status == 1, "Wing picture enters the screen before the contact body")
	check(flyer.phase == 0 and flyer.x == 1000 * S, "Activation does not advance the swing")
	Registry.advance(state, world, 0)
	check(flyer.x == 1000 * S, "Swing starts with a stationary first tick")
	Registry.advance(state, world, 0)
	check(flyer.x == 1000 * S - 48 * 60, "Next swing tick moves at the capped speed")
	# A top contact at the current wave position must use the real actor dispatch.
	state.x = flyer.x
	state.y = flyer.y - 15 * S
	state.vy = 180 * 60
	Registry.contact(state, Sim.JUMP, world)
	check(
		flyer.status == 3 and state.vy == -704 * 60, "Created flyer gives a held-jump stomp bounce"
	)


func flight_frame_contacts() -> void:
	for variant in 5:
		for facing in [-1, 1]:
			for age in [0, 3, 5, 8]:
				var world := course(600)
				var state := State.create(world)
				var flyer: Dictionary = state.entities[0]
				flyer.timer = age
				flyer.facing = facing
				flyer.variant = variant
				# The player's edge is 9 px from the flyer: only frames 1..3 reach it.
				state.x = flyer.x - facing * 21 * S
				state.y = flyer.y - 15 * S
				state.vy = 180 * 60
				Registry.contact(state, Sim.JUMP, world)
				check(
					(
						(flyer.status == 3 and state.vy == -704 * 60)
						if age > 0
						else (flyer.status == 1 and state.vy == 180 * 60)
					),
					"Flight frame body controls contact in both facings and every variant"
				)


func runtime_birth() -> void:
	var world := course(600)
	var state := State.create(world)
	state.frame = 1000
	var flyer := Registry.spawn_dynamic(state, world, "e2", 700 * S, 512 * S, {})
	check(not flyer.is_empty() and flyer.timer == 0, "Runtime birth has no level-intro wave age")
	Registry.advance(state, world, 0)
	check(flyer.y == 512 * S + Motion.sine(1, 180, 12 * S), "Runtime wave ignores the level frame")


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
