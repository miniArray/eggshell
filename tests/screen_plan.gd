extends SceneTree
## Pure camera policy checks; no viewport or simulation state is needed.
const Plan = preload("res://src/view/screen_plan.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	var large_level := Vector2(10000, 10000)
	for case: Array in [
		[Vector2(640, 480), 1.0, Vector2(640, 480)],
		[Vector2(1280, 720), 2.0, Vector2(640, 360)],
		[Vector2(1920, 1080), 2.0, Vector2(960, 540)],
		[Vector2(2560, 1440), 3.0, Vector2(2560.0 / 3, 480)],
		[Vector2(3840, 2160), 5.0, Vector2(768, 432)],
		[Vector2(832, 448), 1.0, Vector2(832, 448)],
	]:
		var plan := Plan.plan(case[0], large_level, large_level / 2)
		check(
			plan == Plan.plan(case[0], large_level, large_level / 2, 1),
			"Explicit density 1 is unchanged"
		)
		check(plan.scale == case[1], "%s uses scale %s" % [case[0], case[1]])
		check(plan.visible.is_equal_approx(case[2]), "%s visible world" % case[0])
	for case: Array in [
		[Vector2(640, 480), 2.0],
		[Vector2(1280, 720), 2.0],
		[Vector2(1920, 1080), 2.0],
		[Vector2(2560, 1440), 4.0],
		[Vector2(3840, 2160), 4.0],
	]:
		var plan := Plan.plan(case[0], large_level, large_level / 2, 2)
		check(plan.scale == case[1], "Density 2 world scale at %s" % case[0])
		check(plan.visible.is_equal_approx(case[0] / case[1]), "Density 2 visible world")
	for density in range(1, 5):
		var plan := Plan.plan(Vector2(1280, 720), Vector2(300, 200), Vector2.ZERO, density)
		check(int(plan.scale) % density == 0, "Bounds raise keeps art scale integral")
		check(plan.visible.x <= 300 and plan.visible.y <= 200, "Density bounds fit")
	# Ratio distance changes at the geometric mean, not the arithmetic midpoint.
	for lower: int in [1, 2, 4]:
		var boundary := sqrt(float(lower * (lower + 1)))
		for delta: float in [-0.0001, 0.0001]:
			var container := Vector2(832, 448) * (boundary + delta)
			var plan := Plan.plan(container, large_level, large_level / 2)
			check(
				plan.scale == float(lower if delta < 0 else lower + 1),
				"Scale changes at ratio boundary %s, delta %s" % [lower, delta]
			)
	for case: Array in [
		[Vector2(1280, 720), Vector2(300, 200), 5.0],
		[Vector2(640, 480), Vector2(800, 200), 3.0],
		[Vector2(640, 480), Vector2(640, 480), 1.0],
		[Vector2(1920, 1080), large_level, 2.0],
		[Vector2(1, 1), Vector2(30, 20), 1.0],
		[Vector2(170, 1280), Vector2(30, 20), 64.0],
		[Vector2(1280, 80), Vector2(30, 20), 43.0],
		[Vector2(1, 1), large_level, 1.0],
		[Vector2(170, 1280), large_level, 1.0],
		[Vector2(1280, 80), large_level, 1.0],
	]:
		for focus: Vector2 in [Vector2(-100, -100), Vector2(15.25, 10.75), large_level * 2]:
			var plan := Plan.plan(case[0], case[1], focus)
			check(plan.scale == case[2], "%s in level %s scale" % [case[0], case[1]])
			check(plan.scale >= 1 and plan.scale == floorf(plan.scale), "Positive integer scale")
			var start: Vector2 = plan.center - plan.visible / 2
			var end: Vector2 = plan.center + plan.visible / 2
			check(start.x >= -0.001 and start.y >= -0.001, "Clamped at level start")
			check(end.x <= case[1].x + 0.001 and end.y <= case[1].y + 0.001, "Clamped at level end")
			check(
				plan.offset.is_equal_approx(case[0] / 2 - plan.center * plan.scale),
				"Offset keeps the clamped center in the container center"
			)
	zoom_checks(large_level)
	print("SCREEN_PLAN_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func zoom_checks(large_level: Vector2) -> void:
	# 1920 by 1080 fits at 2; zoom in stops before fewer than 208 by 112 world pixels.
	var wide := Plan.plan(Vector2(1920, 1080), large_level, large_level / 2)
	check(wide.zoom == 0 and wide.base_scale == 2.0, "No zoom keeps the fitted scale")
	check(wide.zoom_min == -1 and wide.zoom_max == 7, "1920 by 1080 zoom range")
	for zoom in range(-6, 12):
		var plan := Plan.plan(Vector2(1920, 1080), large_level, large_level / 2, 1, zoom)
		check(plan.zoom == clampi(zoom, -1, 7), "Zoom %d clamps into range" % zoom)
		check(plan.scale == 2.0 + plan.zoom, "Zoom %d changes the multiple by whole steps" % zoom)
		check(plan.base_scale == 2.0, "Zoom %d keeps the base scale" % zoom)
		check(
			plan.visible.x >= 208 and plan.visible.y >= 112, "Zoom %d keeps a minimum view" % zoom
		)
	# One screen pixel either side of the zoom-in limit.
	for case: Array in [[Vector2(2400, 1119), 9], [Vector2(2400, 1120), 10]]:
		var plan := Plan.plan(case[0], large_level, large_level / 2, 1, 99)
		check(plan.scale == float(case[1]), "Zoom-in limit at height %d" % case[0].y)
	# Density keeps every art pixel a whole number of screen pixels.
	var dense := Plan.plan(Vector2(3840, 2160), large_level, large_level / 2, 2, -99)
	check(dense.scale == 2.0 and dense.zoom == dense.zoom_min, "Density 2 zooms out to one")
	var closer := Plan.plan(Vector2(3840, 2160), large_level, large_level / 2, 2, 99)
	check(int(closer.scale) % 2 == 0 and closer.visible.y >= 112, "Density 2 zooms in whole")
	# Zoom never shows space outside the level, at any container shape.
	for container: Vector2 in [
		Vector2(1920, 1080), Vector2(832, 448), Vector2(170, 1280), Vector2(1280, 80), Vector2(1, 1)
	]:
		for level: Vector2 in [Vector2(640, 480), Vector2(2000, 300), Vector2(300, 2000)]:
			for zoom: int in [-99, -2, -1, 0, 1, 3, 99]:
				for density in [1, 2]:
					var plan := Plan.plan(container, level, level, density, zoom)
					var start: Vector2 = plan.center - plan.visible / 2
					var end: Vector2 = plan.center + plan.visible / 2
					check(
						start.x >= -0.001 and start.y >= -0.001,
						"Zoom %d at %s in %s starts inside" % [zoom, container, level]
					)
					check(
						end.x <= level.x + 0.001 and end.y <= level.y + 0.001,
						"Zoom %d at %s in %s ends inside" % [zoom, container, level]
					)
					check(plan.zoom_min <= 0 and plan.zoom_max >= 0, "Zero is always in range")
					check(int(plan.scale) % density == 0, "Zoomed scale stays whole per art pixel")
	# A level just larger than the window cannot be zoomed out past its bounds.
	var tight := Plan.plan(Vector2(832, 448), Vector2(900, 500), Vector2(450, 250), 1, -3)
	check(tight.scale == 1.0 and tight.zoom_min == 0, "Fit limits zoom out")


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
