extends SceneTree
## Reader limits, exact replay, storage validation and view independence.

const Fixtures = preload("res://tests/fixtures.gd")
const Reader = preload("res://src/level/level_code.gd")
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Save = preload("res://src/save/snapshot.gd")
const Plan = preload("res://src/view/screen_plan.gd")
const View = preload("res://src/view/level_view.gd")
const Collision = preload("res://src/level/collision_table.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	reader_checks()
	for name: String in ["stride", "endurance", "bounce", "lagoon", "actors", "shapes"]:
		replay_checks(name)
	movement_checks()
	damage_recording()
	print("CORE_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func reader_checks() -> void:
	check(not Reader.parse("{bad").ok, "Invalid JSON rejected")
	check(not Reader.parse("[]").ok, "Top-level array rejected")
	for token: String in ["0x0", "3x-2", "1hh", "-1v", "99999999999999999999999x0"]:
		var code := JSON.stringify({"c2tilemap": true, "width": 1, "height": 1, "data": token})
		check(not Reader.decode_tilemap(code).ok, "Invalid run rejected: " + token)
	for token: String in ["-1", "0", "1h", "1v", "1d", "1hvd"]:
		var code := JSON.stringify({"c2tilemap": true, "width": 1, "height": 1, "data": token})
		check(Reader.decode_tilemap(code).ok, "Valid tile flags: " + token)
	check(
		not Reader.decode_tilemap('{"c2tilemap":true,"width":2,"height":1,"data":"0"}').ok,
		"Short runs rejected"
	)
	check(
		not Reader.decode_tilemap('{"c2tilemap":true,"width":1,"height":1,"data":"2x0"}').ok,
		"Overflow rejected"
	)
	var original: Dictionary = JSON.parse_string(Fixtures.code("stride"))
	original.extra = {"kept": true}
	check(Reader.parse(JSON.stringify(original)).level.extra.kept, "Unknown fields preserved")
	original.startpoint.map = 99
	check(not Reader.parse(JSON.stringify(original)).ok, "Missing starting map rejected")


func replay_checks(name: String) -> void:
	var world := Fixtures.world(name)
	var replay := Fixtures.recording(name)
	var first := State.create(world)
	var second := State.create(world)
	var checkpoint := PackedByteArray()
	var views := []
	for size: Vector2 in [
		Vector2(832, 448),
		Vector2(640, 480),
		Vector2(480, 480),
		Vector2(1280, 720),
		Vector2(1280, 80),
		Vector2(170, 1280)
	]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(size)
		root.add_child(viewport)
		var view := View.new()
		viewport.add_child(view)
		view.setup(world, "")
		views.append([view, size, viewport])
	for frame in replay.size():
		Sim.advance(first, int(replay[frame]), world)
		Sim.advance(second, int(replay[frame]), world)
		var bytes := Save.encode(first)
		check(bytes == Save.encode(second), name + " deterministic tick %d" % frame)
		if frame == 59:
			checkpoint = bytes
		for pair: Array in views:
			pair[0].render(first)
			check(Save.encode(first) == bytes, name + " view never mutates state")
			var plan := Plan.plan(
				pair[1],
				Vector2(world.width, world.height) / State.SCALE,
				Vector2(first.camera_x, first.camera_y) / State.SCALE
			)
			check(
				pair[0]._root.position == plan.offset.round(),
				"View snaps the root offset to screen pixels"
			)
			check(
				(
					(plan.center - plan.visible / 2).x >= -0.001
					and (
						(plan.center + plan.visible / 2).x
						<= float(world.width) / State.SCALE + 0.001
					)
				),
				"View stays within horizontal bounds"
			)
			check(
				(
					(plan.center - plan.visible / 2).y >= -0.001
					and (
						(plan.center + plan.visible / 2).y
						<= float(world.height) / State.SCALE + 0.001
					)
				),
				"View stays within vertical bounds"
			)
	var restored := Save.decode(checkpoint, world.identity)
	check(restored.ok, name + " checkpoint decodes")
	if restored.ok:
		for frame in range(60, replay.size()):
			Sim.advance(restored.state, int(replay[frame]), world)
		check(Save.encode(first) == Save.encode(restored.state), name + " restored future matches")
	check(first.goal_reached == 1, name + " recording reaches goal")
	check(first.deaths == 0, name + " no pit resets")
	var final := Save.encode(first)
	Sim.advance(first, 15, world)
	check(Save.encode(first) == final, name + " goal freezes all state")
	for variant: PackedByteArray in [final.slice(0, -1), PackedByteArray()]:
		check(not Save.decode(variant, world.identity).ok, "Bad length rejected")
	check(not Save.decode(final, "different").ok, "Wrong identity rejected")
	var wrong := final.duplicate()
	wrong.encode_u32(8, 1)
	check(not Save.decode(wrong, world.identity).ok, "Old version rejected")
	wrong = final.duplicate()
	wrong[40] ^= 1
	check(not Save.decode(wrong, world.identity).ok, "Bad checksum rejected")
	print(
		"COURSE ",
		name,
		" goal=",
		first.goal_reached,
		" tick=",
		first.frame,
		" deaths=",
		first.deaths,
		" hits=",
		first.hits,
		" x=",
		float(first.x) / State.SCALE
	)
	for pair: Array in views:
		pair[2].free()


func movement_checks() -> void:
	var world := Fixtures.world("stride")
	world.goals.clear()
	var walk := State.create(world)
	var run := State.create(world)
	for tick in 60:
		Sim.advance(walk, Sim.RIGHT, world)
		Sim.advance(run, Sim.RIGHT | Sim.RUN, world)
	check(walk.vx == Sim.WALK_SPEED and run.vx == Sim.RUN_SPEED, "Walk and run caps")
	# The old run bit is the use action now; there is no run modifier, so it adds no speed.
	check(run.x <= walk.x, "The legacy run bit adds no speed")
	var jump := State.create(world)
	Sim.advance(jump, 0, world)
	var minimum: int = jump.y
	for tick in 90:
		Sim.advance(jump, Sim.JUMP, world)
		minimum = mini(minimum, jump.y)
	check(minimum < world.spawn_y - 140 * State.SCALE, "Jump clears 140 pixels")
	# A held jump flutters, so the landing comes after the button is released.
	for tick in 120:
		if jump.on_floor == 1:
			break
		Sim.advance(jump, 0, world)
	check(jump.on_floor == 1, "Jump lands")
	var flutter := State.create(world)
	Sim.advance(flutter, 0, world)
	for tick in 33:
		Sim.advance(flutter, Sim.JUMP if tick < 27 or tick >= 29 else 0, world)
	check(flutter.flutter_remaining > 0, "Release and re-hold starts flutter")
	var facts := Collision.read()
	check(World.tile_bounds(14, facts.tilemaps.garden32).is_empty(), "Decorative tile is non-solid")
	check(
		(
			World.tile_bounds(4, facts.tilemaps.garden64_1)
			== [0, 32 * State.SCALE, 64 * State.SCALE, 64 * State.SCALE]
		),
		"Half tile bounds"
	)
	check(
		(
			World.tile_bounds(4 | 0x40000000, facts.tilemaps.garden64_1)
			== [0, 0, 64 * State.SCALE, 32 * State.SCALE]
		),
		"Flipped collision bounds"
	)


func damage_recording() -> void:
	var world := Fixtures.world("stride")
	var state := State.create(world)
	var replay: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/stride.damage.input.json")
	)
	var was_separated := false
	var recovered := false
	for input: int in replay:
		Sim.advance(state, input, world)
		was_separated = was_separated or state.separated == 1
		recovered = recovered or (was_separated and state.separated == 0)
	check(state.hits > 0, "Original damage recording really takes a hit")
	check(recovered, "Recorded inputs touch the recovery marker without state injection")
	check(state.goal_reached == 1 and state.deaths == 0, "Damage recording finishes")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
