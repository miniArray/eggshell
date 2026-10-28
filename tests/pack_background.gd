extends SceneTree
## Repeated slots may collapse only when compositing and layer order stay unchanged.
const Background = preload("res://src/view/pack_background.gd")
var _checks := 0
var _failures := 0
var _path := "/tmp/eggshell-background-%d" % OS.get_process_id()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(_path)
	for alpha: float in [0.0, 0.5, 1.0, 1.0 / 255, 254.0 / 255]:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.4, 0.6, 1.0))
		image.set_pixel(0, 0, Color(0.7, 0.2, 0.3, alpha))
		image.save_png(_path.path_join("alpha-%s.png" % str(alpha)))
	var opaque := {"file": "alpha-1.0.png"}
	var cutout := {"file": "alpha-0.0.png"}
	var translucent := {"file": "alpha-0.5.png"}
	check_layers({"0": {"layers": [opaque]}}, {}, 1, "Implicit zero slots draw opaque art once")
	check_layers(
		{"0": {"layers": [opaque, cutout]}}, {}, 2, "Binary-alpha multilayer slots are idempotent"
	)
	check_layers(
		{"0": {"layers": [opaque, translucent]}}, {}, 6, "Partial alpha keeps triple composition"
	)
	check_layers(
		{"0": {"layers": [opaque]}},
		{"bg2": "missing"},
		1,
		"An empty slot does not interrupt identical drawn groups"
	)
	check_layers(
		{"0": {"layers": [opaque]}, "1": {"layers": [cutout]}},
		{"bg2": "1"},
		3,
		"Intervening art keeps painter order"
	)
	check_layers(
		{"0": {"layers": [opaque], "slots": {"bg2": {"scroll": [0.5, 1]}}}},
		{},
		3,
		"Slot scroll differences survive"
	)
	check_layers(
		{"0": {"layers": [opaque], "slots": {"bg2": {"offset_by_height": {"448": [0, 8]}}}}},
		{"height": 448},
		3,
		"Height-specific offsets survive"
	)
	check_layers(
		{"0": {"layers": [opaque], "variants": {"1": {"layers": [cutout]}}}},
		{"bg2": "0,1"},
		3,
		"Variant choices survive"
	)
	check_layers(
		{"0": {"layers": [opaque]}, "1": {"layers": [opaque]}},
		{"bg2": "1"},
		3,
		"Distinct entry ids survive"
	)
	check_layers(
		{"0": {"layers": [{"animation": {"fps": 6, "frames": [opaque, translucent]}}]}},
		{},
		3,
		"Every animation frame must be safe"
	)
	check_layers(
		{"0": {"layers": [{"animation": {"fps": 6, "frames": [opaque, cutout]}}]}},
		{},
		1,
		"Binary-alpha animation can collapse"
	)
	for alpha: float in [1.0 / 255, 254.0 / 255]:
		check_layers(
			{"0": {"layers": [{"file": "alpha-%s.png" % str(alpha)}]}},
			{},
			3,
			"Near-binary fractional alpha must still composite three times"
		)
	check_layers({}, {}, 0, "Placeholder adds no layers")
	for file: String in DirAccess.get_files_at(_path):
		DirAccess.remove_absolute(_path.path_join(file))
	DirAccess.remove_absolute(_path)
	print("PACK_BACKGROUND_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check_layers(backgrounds: Dictionary, map: Dictionary, count: int, label: String) -> void:
	var node := Background.new()
	node.setup({"backgrounds": backgrounds}, _path, map)
	_checks += 1
	if node._layers.size() != count:
		_failures += 1
		printerr("FAIL: %s: expected %d, got %d" % [label, count, node._layers.size()])
	node.free()
