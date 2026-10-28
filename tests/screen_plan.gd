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
		check(plan.scale == case[1], "%s uses scale %s" % [case[0], case[1]])
		check(plan.visible.is_equal_approx(case[2]), "%s visible world" % case[0])
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
	print("SCREEN_PLAN_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
