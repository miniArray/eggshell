extends SceneTree
## GPU assertions for optional HUD rectangles and safe background compositing.
const Hud = preload("res://src/view/hud.gd")
const Background = preload("res://src/view/pack_background.gd")
var _checks := 0
var _failures := 0
var _path := "/tmp/eggshell-pack-view-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_path)
	var icon := Image.create(12, 20, false, Image.FORMAT_RGBA8)
	icon.fill(Color.WHITE)
	icon.save_png(_path.path_join("icon.png"))
	for density: int in [1, 2]:
		for size: Vector2i in [Vector2i(170, 480), Vector2i(640, 480), Vector2i(1920, 1080)]:
			for padding: int in [2, 16]:
				await check_hud(density, size, padding)
	for alpha: float in [0.0, 0.5, 1.0]:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.4, 0.6, 1))
		image.fill_rect(Rect2i(2, 3, 8, 7), Color(0.8, 0.3, 0.1, alpha))
		image.save_png(_path.path_join("layer.png"))
		await check_background()
	for file: String in DirAccess.get_files_at(_path):
		DirAccess.remove_absolute(_path.path_join(file))
	DirAccess.remove_absolute(_path)
	print("PACK_VIEW_RENDER_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func viewport_at(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func check_hud(density: int, size: Vector2i, padding: int) -> void:
	var viewport := viewport_at(size)
	var world_root := Node2D.new()
	world_root.scale = Vector2.ONE * density * (2 if size.x > 1000 else 1)
	world_root.hide()
	viewport.add_child(world_root)
	var hud := Hud.new()
	hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(hud)
	var rgb := Color8(12, 34, 56)
	var manifest := {"density": density, "hud": {"countdown": {"file": "icon.png"}}}
	hud.setup(manifest, _path)
	var state := {"x": 0, "y": 0, "facing": 1, "frame": 0}
	hud.render(state, size, world_root)
	await RenderingServer.frame_post_draw
	var legacy := viewport.get_texture().get_image().get_data()
	# Exercise direct callers as well as manifests already sanitized by Pack.read.
	manifest.hud["backing"] = {"color": [0, 0, 256]}
	hud.setup(manifest, _path)
	hud.render(state, size, world_root)
	await RenderingServer.frame_post_draw
	check(
		viewport.get_texture().get_image().get_data() == legacy,
		"Invalid backing preserves legacy frame"
	)
	manifest.hud.backing = {"color": [12, 34, 56], "padding": padding}
	hud.setup(manifest, _path)
	hud.render(state, size, world_root)
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var scale: float = hud._plan.scale
	for box: Rect2 in hud._plan.backings:
		var screen := Rect2i(box.position * scale, box.size * scale)
		for y in range(maxi(0, screen.position.y), mini(size.y, screen.end.y)):
			for x in range(maxi(0, screen.position.x), mini(size.x, screen.end.x)):
				if (
					x < screen.position.x + padding * scale
					or x >= screen.end.x - padding * scale
					or y < screen.position.y + padding * scale
					or y >= screen.end.y - padding * scale
				):
					check(
						pixels.get_pixel(x, y).is_equal_approx(rgb),
						"Backing perimeter is opaque exact RGB without blended edges"
					)
	viewport.free()


func check_background() -> void:
	var layer := {"file": "layer.png", "scroll": [0.25, 0.5]}
	var overlay := {"file": "icon.png", "offset": [4, 5]}
	var manifest := {"backgrounds": {"0": {"layers": [layer, overlay]}}}
	# Different ids force the original three groups without changing any layer.
	manifest.backgrounds["1"] = manifest.backgrounds["0"]
	manifest.backgrounds["2"] = manifest.backgrounds["0"]
	var images: Array[PackedByteArray] = []
	for map: Dictionary in [{}, {"bg2": "1", "bg3": "2"}]:
		var viewport := viewport_at(Vector2i(128, 96))
		var background := Background.new()
		background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(background)
		background.setup(manifest, _path, map)
		background.render(
			{
				"center": Vector2(64, 48),
				"visible": Vector2(128, 96),
				"scale": 1,
				"offset": Vector2.ZERO
			},
			0
		)
		await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image().get_data())
		viewport.free()
	check(
		images[0] == images[1],
		"Deduplicated and original triple-slot GPU frames are byte-identical"
	)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		if _failures <= 5:
			printerr("FAIL: " + label)
