extends SceneTree
## Off-screen presentation sleeps; re-entry samples the current saved tick before drawing.
const InputPack = preload("res://tests/density_pack.gd")
const View = preload("res://src/view/level_view.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := InputPack.create()
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(path.path_join("manifest.json"))
	)
	manifest.objects.o1 = {
		"anchor": "position",
		"animations":
		{
			"coin":
			{
				"fps": 60,
				"frames":
				[
					{"file": "object.png", "origin": [6, 18]},
					{"file": "object.png", "origin": [106, 118]}
				]
			}
		}
	}
	InputPack.write_json(path, "manifest.json", manifest)
	var world := InputPack.world()
	var state := State.create(world)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var view := View.new()
	viewport.add_child(view)
	view.setup(world, path)
	state.camera_x = 200 * State.SCALE
	state.camera_y = 250 * State.SCALE
	view.render(state)
	var coin: Sprite2D = view._placed_nodes.coin
	check(coin.visible, "A visible placement is presented")
	state.camera_x = 3000 * State.SCALE
	state.camera_y = 3000 * State.SCALE
	state.frame = 1
	for entity: Dictionary in state.entities:
		if entity.id == "coin":
			entity.phase = 8
	var before := Snapshot.encode(state)
	view.render(state)
	check(not coin.visible, "A proven off-screen placement is hidden")
	check(coin.offset == Vector2(-6, -18), "Off-screen placements do not sample animation")
	state.camera_x = 200 * State.SCALE
	state.camera_y = 250 * State.SCALE
	view.render(state)
	check(coin.visible, "An entering placement is visible in this render")
	check(coin.offset == Vector2(-106, -118), "Entry samples this frame, not the last visible tick")
	state.camera_x = 3000 * State.SCALE
	state.camera_y = 3000 * State.SCALE
	check(Snapshot.encode(state) == before, "Visibility never changes simulation bytes")
	# A replaced state at the same tick must not reuse a stale presentation.
	var restored := Snapshot.decode(before, world.identity, world)
	check(restored.ok, "The visibility fixture restores")
	if restored.ok:
		var saved: Dictionary = restored.state
		saved.camera_x = 200 * State.SCALE
		saved.camera_y = 250 * State.SCALE
		saved.frame = 0
		for entity: Dictionary in saved.entities:
			if entity.id == "coin":
				entity.phase = 0
		view.render(saved)
		check(coin.visible and coin.offset == Vector2(-6, -18), "Restore refreshes entering art")
	view.free()
	viewport.free()
	InputPack.remove(path)
	print("VIEW_VISIBILITY_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
