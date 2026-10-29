extends RefCounted
## Integer oriented rectangles. Angles are clockwise thousandths of a degree.
const Motion = preload("res://src/sim/enemy_motion.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const World = preload("res://src/sim/world.gd")
const S := preload("res://src/sim/units.gd").SCALE
const TURN := 360000
## Geometry depends only on these integer arguments, not on entity state. Bound the
## shared transient cache so changing angles cannot retain unlimited shapes.
const MAX_GEOMETRY := 1024
static var _geometry := {}


static func angle_wrap(angle: int) -> int:
	return (angle % TURN + TURN) % TURN


static func vector(angle: int, length: int) -> Array[int]:
	var x := Motion.sine(angle_wrap(angle + 90000), TURN, 1000000)
	var y := Motion.sine(angle_wrap(angle), TURN, 1000000)
	var magnitude := Motion.root(x * x + y * y)
	return [length * x / magnitude, length * y / magnitude]


static func points(angle: int, rectangle: Array) -> PackedInt64Array:
	return _shape(angle, rectangle).points.duplicate()


static func _shape(angle: int, rectangle: Array) -> Dictionary:
	var key := [angle_wrap(angle), rectangle[0], rectangle[1], rectangle[2], rectangle[3]]
	var known: Variant = _geometry.get(key)
	if known != null:
		return known
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
	var shape := {"points": result, "bounds": World.polygon_bounds(result)}
	if _geometry.size() >= MAX_GEOMETRY:
		_geometry.clear()
	_geometry[key] = shape
	return shape


static func bounds(angle: int, rectangle: Array) -> Array:
	# Keep mutable cache storage private, as with points().
	return _shape(angle, rectangle).bounds.duplicate()


static func overlaps(angle: int, rectangle: Array, probe: Array, x := 0, y := 0) -> bool:
	return Polygon.overlaps_box(
		_shape(angle, rectangle).points, probe[0] - x, probe[1] - y, probe[2] - x, probe[3] - y
	)
