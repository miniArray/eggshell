extends SceneTree
## Repeated oriented geometry must keep the original integer rounding and independent
## return values. This is the geometry used by gate sensors and live solid pad probes.
const Turn = preload("res://src/sim/oriented_box.gd")
const World = preload("res://src/sim/world.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const S := 3600
var checks := 0
var failures := 0
var seed := 31337


func _initialize() -> void:
	for index in 1100:
		var angle := next(720000) - 360000
		var rectangle := [-64 * S, -16 * S, 64 * S, (16 + next(33)) * S]
		var expected := original_points(angle, rectangle)
		for repeat in 2:
			check(Turn.points(angle, rectangle) == expected, "integer corners")
			check(Turn.bounds(angle, rectangle) == World.polygon_bounds(expected), "integer bounds")
			var x := (next(200) - 100) * S
			var y := (next(200) - 100) * S
			var probe := [x, y, x + next(32) * S, y + next(32) * S]
			check(
				(
					Turn.overlaps(angle, rectangle, probe, 3 * S, -5 * S)
					== Polygon.overlaps_box(
						expected,
						probe[0] - 3 * S,
						probe[1] + 5 * S,
						probe[2] - 3 * S,
						probe[3] + 5 * S
					)
				),
				"translated narrow phase"
			)
	# Callers receive values, not mutable cache storage or mutable cache keys.
	var rectangle := [-64 * S, -16 * S, 64 * S, 48 * S]
	var expected := original_points(37000, rectangle)
	var points := Turn.points(37000, rectangle)
	var bounds := Turn.bounds(37000, rectangle)
	points[0] = 0
	bounds[0] = 0
	rectangle[0] = 0
	var original := [-64 * S, -16 * S, 64 * S, 48 * S]
	check(Turn.points(37000, original) == expected, "points do not share writes")
	check(
		Turn.bounds(37000, original) == World.polygon_bounds(expected), "bounds do not share writes"
	)
	check(
		Turn.points(37000, rectangle) == original_points(37000, rectangle),
		"rectangle changes are keyed"
	)
	print("ORIENTED_BOX_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func original_points(angle: int, rectangle: Array) -> PackedInt64Array:
	var x := Motion.sine(Turn.angle_wrap(angle + 90000), Turn.TURN, 1000000)
	var y := Motion.sine(Turn.angle_wrap(angle), Turn.TURN, 1000000)
	var magnitude := Motion.root(x * x + y * y)
	var basis := [S * x / magnitude, S * y / magnitude]
	var result := PackedInt64Array()
	for corner: Array in [
		[rectangle[0], rectangle[1]],
		[rectangle[2], rectangle[1]],
		[rectangle[2], rectangle[3]],
		[rectangle[0], rectangle[3]]
	]:
		result.append((corner[0] * basis[0] - corner[1] * basis[1]) / S)
		result.append((corner[0] * basis[1] + corner[1] * basis[0]) / S)
	return result


func next(limit: int) -> int:
	seed = (seed * 1103515245 + 12345) % 2147483648
	return (seed >> 16) % limit


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
