extends SceneTree
## Optional backing validation and layout use the same production plan as drawing.
const Hud = preload("res://src/view/hud.gd")
const Pack = preload("res://src/level/asset_pack.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	for padding: int in [0, 2, 5, 16]:
		check(Pack.hud_backing_ok({"color": [0, 127, 255], "padding": padding}), "Valid backing")
		for container: Vector2 in [
			Vector2(832, 448), Vector2(170, 800), Vector2(1280, 80), Vector2(1, 1)
		]:
			var widths: Array[float] = [63.5, 72.25, 80.0, 54.5]
			var heights: Array[float] = [16.0, 21.5, 16.0, 30.0]
			for factor: int in [1, 2, 3]:
				var plan := Hud.dense_plan(container, widths, heights, factor, padding)
				check_boxes(plan, widths, heights, padding)
			var normal := Hud.plan(container, widths, 24, padding)
			check_boxes(normal, widths, [16.0, 16.0, 16.0, 16.0], padding)
	check(Pack.hud_backing_ok({"color": [12, 34, 56]}), "Padding defaults to two")
	for value: Variant in [
		null,
		false,
		[],
		{},
		{"color": [1, 2]},
		{"color": [1, 2, 3, 4]},
		{"color": [1, -1, 3]},
		{"color": [1, 256, 3]},
		{"color": [1, 2.5, 3]},
		{"color": [true, 2, 3]},
		{"color": ["1", 2, 3]},
		{"color": [NAN, 2, 3]},
		{"color": [1, 2, 3], "padding": -1},
		{"color": [1, 2, 3], "padding": 17},
		{"color": [1, 2, 3], "padding": 1.5},
		{"color": [1, 2, 3], "padding": true},
		{"color": [1, 2, 3], "padding": "2"},
		{"color": [1, 2, 3], "padding": INF}
	]:
		check(not Pack.hud_backing_ok(value), "Invalid backing ignored")
	check(
		not Hud.plan(Vector2(832, 448), [40.0]).has("backings"), "Legacy normal plan has no backing"
	)
	check(
		not Hud.dense_plan(Vector2(832, 448), [40.0], [16.0], 1).has("backings"),
		"Legacy dense plan has no backing"
	)
	print("HUD_BACKING_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check_boxes(
	plan: Dictionary, widths: Array[float], heights: Array[float], padding: int
) -> void:
	check(plan.backings.size() == widths.size(), "One backing per readout")
	for index in widths.size():
		var box: Rect2 = plan.backings[index]
		check(
			box.position == box.position.round() and box.end == box.end.round(),
			"Whole HUD-scale edges"
		)
		var content := Rect2(plan.positions[index], Vector2(widths[index], heights[index]))
		check(box.encloses(content.grow(padding)), "Backing encloses icon and text plus padding")
		for previous in index:
			check(
				not box.intersects(plan.backings[previous]),
				"Wrapped rows and adjacent backings do not overlap"
			)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
