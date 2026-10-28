extends SceneTree
## The same input drives the simulation while the view draws at 60, 120 and 144 Hz and
## at several zoom steps. The full state must match a view-free run at every step, and
## a drawn frame must never change it. Every step compares the complete serialized
## state dictionary; snapshot bytes are compared every CHECKPOINT steps and at the end.
## View nodes are built; no frame is rendered and no audio plays.
const Fixtures = preload("res://tests/fixtures.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const View = preload("res://src/view/level_view.gd")
const FrameLoop = preload("res://src/view/frame_loop.gd")
const AudioPlayer = preload("res://src/view/audio_player.gd")
const AudioMap = preload("res://src/view/pack_audio.gd")
const STEPS := 300
const CHECKPOINT := 50
const RATES := [60, 120, 144]
const ZOOMS := [-1, 0, 2]
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for name: String in ["actors", "lagoon"]:
		var world := Fixtures.world(name)
		var inputs := Fixtures.recording(name).slice(0, STEPS)
		var reference := reference_bytes(world, inputs)
		for rate: int in RATES:
			for zoom: int in ZOOMS:
				drive(name, world, inputs, reference, rate, zoom)
	print("VIEW_INVARIANCE_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## Per step: the serialized state, and snapshot bytes at checkpoints (else empty).
static func reference_bytes(world: Dictionary, inputs: Array) -> Array:
	var state := State.create(world)
	var result := []
	for index in inputs.size():
		Sim.advance(state, int(inputs[index]), world)
		result.append([var_to_bytes(state), snapshot_at(state, index, inputs.size())])
	return result


static func snapshot_at(state: Dictionary, index: int, count: int) -> PackedByteArray:
	if (index + 1) % CHECKPOINT == 0 or index == count - 1:
		return Snapshot.encode(state)
	return PackedByteArray()


func drive(
	name: String, world: Dictionary, inputs: Array, reference: Array, rate: int, zoom: int
) -> void:
	var label := "%s at %d Hz, zoom %d" % [name, rate, zoom]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.setup(world, "")
	view.zoom = zoom
	var audio := AudioPlayer.create(AudioMap.new(), world, {}, true)
	root.add_child(audio)
	var loop := FrameLoop.new()
	loop.smooth = FrameLoop.wants_smooth("auto", rate)
	var state := State.create(world)
	var step := 0
	var steps_matched := true
	var frames_clean := true
	var observed_once := true
	var blended := 0
	var between := true
	var elapsed := 0.0
	var frames := 0
	var from_x: int = state.x
	while step < inputs.size():
		# One drawn frame lasts 1/rate s; whole fixed steps run first, as in the engine.
		frames += 1
		elapsed = frames * 60.0 / rate - step
		while elapsed >= 1.0 - 1e-9 and step < inputs.size():
			elapsed -= 1.0
			loop.tick()
			from_x = state.x
			loop.step(state, int(inputs[step]), world, audio)
			steps_matched = (
				steps_matched
				and var_to_bytes(state) == reference[step][0]
				and snapshot_at(state, step, inputs.size()) == reference[step][1]
			)
			observed_once = observed_once and audio.observations == step + 1
			step += 1
		var bytes := var_to_bytes(state)
		var observations: int = audio.observations
		var picture := loop.picture(state, clampf(elapsed, 0.0, 1.0))
		if not is_same(picture, state):
			blended += 1
		view.render(picture)
		frames_clean = (
			frames_clean and var_to_bytes(state) == bytes and audio.observations == observations
		)
		var low := mini(from_x, state.x) - 1
		var high := maxi(from_x, state.x) + 1
		between = between and int(picture.x) >= low and int(picture.x) <= high
	check(steps_matched, label + ": state matches the view-free run at every step")
	check(frames_clean, label + ": drawing never changes state or observes sound")
	check(observed_once, label + ": sound observes once per step")
	check(between, label + ": pictures stay between steps")
	check(
		view.plan.zoom == clampi(zoom, view.plan.zoom_min, view.plan.zoom_max),
		label + ": the view applies the clamped zoom"
	)
	if rate > 60:
		check(blended > 0, label + ": high refresh draws blended pictures")
	else:
		check(blended == 0, label + ": 60 Hz draws saved states")
	view.free()
	viewport.free()
	audio.free()


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
