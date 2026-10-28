extends RefCounted
## Integer oriented rectangles. Angles are clockwise thousandths of a degree.
const Motion = preload("res://src/sim/enemy_motion.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const TURN := 360000


static func angle_wrap(angle: int) -> int:
	return (angle % TURN + TURN) % TURN


static func vector(angle: int, length: int) -> Array[int]:
	var x := Motion.sine(angle_wrap(angle + 90000), TURN, 1000000)
	var y := Motion.sine(angle_wrap(angle), TURN, 1000000)
	var magnitude := Motion.root(x * x + y * y)
	return [length * x / magnitude, length * y / magnitude]


static func points(angle: int, rectangle: Array) -> PackedInt64Array:
	var basis := vector(angle, S)
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


static func bounds(angle: int, rectangle: Array) -> Array:
	return World.polygon_bounds(points(angle, rectangle))


static func overlaps(angle: int, rectangle: Array, probe: Array, x := 0, y := 0) -> bool:
	return Polygon.overlaps_box(
		points(angle, rectangle), probe[0] - x, probe[1] - y, probe[2] - x, probe[3] - y
	)
