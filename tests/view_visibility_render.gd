extends SceneTree
## GPU oracle: the same production view, fully updated vs viewport-aware. No private art.
const InputPack = preload("res://tests/density_pack.gd")
const StressPack = preload("res://tests/visibility_pack.gd")
const View = preload("res://src/view/level_view.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Registry = preload("res://src/sim/registry.gd")
const Maps = preload("res://src/sim/maps.gd")
const Life = preload("res://src/sim/life.gd")
const Motion = preload("res://src/view/view_motion.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
var _checks := 0
var _failures := 0
var _ports: Array[SubViewport] = []
var _views: Array[Node2D] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Visibility parity requires a rendering display")
		quit(1)
		return
	for density: int in [1, 2, 4]:
		var path := StressPack.create(density)
		var world := StressPack.world()
		for aware: bool in [false, true]:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(640, 480)
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			_ports.append(viewport)
			var view := View.new()
			view.viewport_aware = aware
			viewport.add_child(view)
			view.setup(world, path)
			_views.append(view)
		var state := State.create(world)
		var runtime := Registry.spawn_dynamic(
			state, world, "o1", 240 * State.SCALE, 250 * State.SCALE, {}
		)
		check(not runtime.is_empty(), "Runtime stress placement is valid")
		for size: Vector2i in [Vector2i(640, 480), Vector2i(160, 768), Vector2i(1024, 128)]:
			for viewport: SubViewport in _ports:
				viewport.size = size
			for zoom: int in [0, 2]:
				for view: Node2D in _views:
					view.zoom = zoom
				for point: Vector2 in [
					Vector2.ZERO,
					Vector2(200, 250),
					Vector2(700, 700),
					Vector2(1500, 1500),
					Vector2(2000, 2300),
					Vector2(3300, 3300),
					Vector2(4096, 4096),
					Vector2(200, 250)
				]:
					for tick in 2:
						Sim.advance(state, 0, world)
						state.camera_x = roundi(point.x * State.SCALE)
						state.camera_y = roundi(point.y * State.SCALE)
						for entity: Dictionary in state.entities:
							if entity.code in ["o1", "o3"]:
								entity.phase = 8 * tick
						await parity(
							state,
							(
								"density %d size %s zoom %d at %s tick %d"
								% [density, size, zoom, point, tick]
							)
						)
		# A restore, a map switch, and a return to an already built map cannot retain
		# hidden nodes or stale animation frames from the previous camera.
		var restored := Snapshot.decode(Snapshot.encode(state), world.identity, world)
		check(restored.ok, "Stress state restores")
		if restored.ok:
			state = restored.state
			state.camera_x = 200 * State.SCALE
			state.camera_y = 250 * State.SCALE
			await parity(state, "restored")
		for map_index: int in [2, 1]:
			check(
				Maps.change(
					state,
					world,
					map_index,
					200 * State.SCALE,
					250 * State.SCALE,
					Registry.spawn_map
				),
				"Stress map changes"
			)
			await parity(state, "map %d" % map_index)
		var pose := Motion.capture(state)
		Sim.advance(state, 2, world)
		await parity(Motion.blend(pose, state, 0.5), "120 Hz interpolated picture")
		check(Life.touch_goal(state, {"x": state.x, "y": state.y}), "Goal sequence starts")
		for tick in 4:
			Sim.advance(state, 0, world)
			await parity(state, "goal tick %d" % tick)
		for viewport: SubViewport in _ports:
			viewport.free()
		_ports.clear()
		_views.clear()
		InputPack.remove(path)
	print("VIEW_VISIBILITY_RENDER_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func parity(state: Dictionary, label: String) -> void:
	var before := var_to_bytes(state)
	for view: Node2D in _views:
		view.render(state)
	check(var_to_bytes(state) == before, label + ": drawing does not write state")
	await RenderingServer.frame_post_draw
	var expected := _ports[0].get_texture().get_image()
	var actual := _ports[1].get_texture().get_image()
	check(actual.get_data() == expected.get_data(), label + ": GPU bytes match the uncullled view")


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		if _failures <= 10:
			printerr("FAIL: " + label)
