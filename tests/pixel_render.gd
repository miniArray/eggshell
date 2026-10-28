extends SceneTree
## GPU readback of the production view. Run without --headless (or under Xvfb).
const InputPack = preload("res://tests/density_pack.gd")
const View = preload("res://src/view/level_view.gd")
const State = preload("res://src/sim/play_state.gd")
const Frames = preload("res://src/view/pack_frames.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GPU check requires a rendering display, not --headless")
		quit(1)
		return
	var path := InputPack.create()
	var world := InputPack.world()
	for density: int in [1, 2]:
		var manifest: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(path.path_join("manifest.json"))
		)
		manifest.density = density
		InputPack.write_json(path, "manifest.json", manifest)
		for size: Vector2i in [Vector2i(640, 480), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
			var viewport := SubViewport.new()
			viewport.size = size
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			viewport.transparent_bg = true
			root.add_child(viewport)
			var view := View.new()
			viewport.add_child(view)
			view.setup(world, path)
			var state := State.create(world)
			# Odd screen/root phases and a sub-world-pixel saved position.
			state.x = 1200 * State.SCALE + 1357
			state.y = 1200 * State.SCALE + 2345
			state.camera_x = state.x + 3789
			state.camera_y = state.y - 28 * State.SCALE + 2345
			for turn: int in [0, 1, 2, 3]:
				for facing: int in [-1, 1]:
					state.facing = facing
					state.frame = turn % 2
					view.render(state)
					for node in view._root.get_children():
						if node is CanvasItem:
							node.visible = node == view._player
					view.get_node("RunHud").hide()
					view._effects.hide()
					if density > 1:
						Frames.unsnap(view._player)
					view._player.rotation = turn * PI / 2
					if density > 1:
						Frames.snap(view._player, view._root.scale.x)
					await RenderingServer.frame_post_draw
					var pixels := viewport.get_texture().get_image()
					check_pixels(view._player, pixels, density)
			if density == 2:
				view._player.hide()
				var hud := view.get_node("RunHud")
				hud._items.clear()
				hud._items.append({"text": "01", "icon": 0})
				hud._plan = {"scale": view._root.scale.x / density, "positions": [Vector2(8, 8)]}
				hud.show()
				hud.queue_redraw()
				await RenderingServer.frame_post_draw
				var pixels := viewport.get_texture().get_image()
				var factor := roundi(hud._plan.scale)
				var art := Image.load_from_file(path.path_join("object.png"))
				for y in 20:
					for x in 16:
						for sy in factor:
							for sx in factor:
								check(
									(
										pixels
										. get_pixel((8 + x) * factor + sx, (8 + y) * factor + sy)
										. is_equal_approx(art.get_pixel(x, y))
									),
									"HUD icon keeps every art pixel"
								)
				for y in 10:
					for x in 16:
						for sy in factor:
							for sx in factor:
								check(
									(
										pixels
										. get_pixel((32 + x) * factor + sx, (8 + y) * factor + sy)
										. is_equal_approx(art.get_pixel(x, y))
									),
									"Bitmap glyph keeps every art pixel"
								)
			viewport.free()
	InputPack.remove(path)
	print("PIXEL_RENDER_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check_pixels(sprite: Sprite2D, pixels: Image, density: int) -> void:
	var transform := sprite.get_global_transform()
	var art := sprite.texture.get_image()
	var factor := roundi(transform.x.length())
	check(factor >= 1, "Every art pixel gets at least one screen pixel")
	# Test the interior of every art-pixel block, not just the sprite's bounding box.
	# A half-screen-pixel corner at m=2 would otherwise give alternating 1/3 widths.
	for y in art.get_height():
		for x in art.get_width():
			var expected := art.get_pixel(x, y)
			var origin := transform * (Vector2(x, y) + sprite.offset)
			for sy in factor:
				for sx in factor:
					var point := (
						origin
						+ transform.basis_xform(Vector2((sx + 0.5) / factor, (sy + 0.5) / factor))
					)
					var at := Vector2i(point.floor())
					check(
						pixels.get_pixelv(at).is_equal_approx(expected),
						"Uniform unblended art pixel, density %d" % density
					)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		if _failures <= 5:
			printerr("FAIL: " + label)
