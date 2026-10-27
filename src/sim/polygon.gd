extends RefCounted
## Closed polygon overlap in tile-local integer coordinates. Concave shapes are allowed.


static func overlaps_box(
	points: PackedInt64Array, left: int, top: int, right: int, bottom: int
) -> bool:
	if points.is_empty():
		return false
	if contains_point(points, left, top):
		return true
	for index in range(0, points.size(), 2):
		var next := (index + 2) % points.size()
		var ax := points[index]
		var ay := points[index + 1]
		var bx := points[next]
		var by := points[next + 1]
		if left <= ax and ax <= right and top <= ay and ay <= bottom:
			return true
		if (
			segments_meet(ax, ay, bx, by, left, top, right, top)
			or segments_meet(ax, ay, bx, by, right, top, right, bottom)
			or segments_meet(ax, ay, bx, by, right, bottom, left, bottom)
			or segments_meet(ax, ay, bx, by, left, bottom, left, top)
		):
			return true
	return false


static func contains_point(points: PackedInt64Array, x: int, y: int) -> bool:
	var inside := false
	for index in range(0, points.size(), 2):
		var next := (index + 2) % points.size()
		var ax := points[index]
		var ay := points[index + 1]
		var bx := points[next]
		var by := points[next + 1]
		var cross := (bx - ax) * (y - ay) - (by - ay) * (x - ax)
		if (
			cross == 0
			and mini(ax, bx) <= x
			and x <= maxi(ax, bx)
			and mini(ay, by) <= y
			and y <= maxi(ay, by)
		):
			return true
		# Compare the ray crossing without division, including for reversed edges.
		if (ay > y) != (by > y) and (cross > 0) == (by > ay):
			inside = not inside
	return inside


static func segments_meet(
	ax: int, ay: int, bx: int, by: int, cx: int, cy: int, dx: int, dy: int
) -> bool:
	if (
		maxi(ax, bx) < mini(cx, dx)
		or maxi(cx, dx) < mini(ax, bx)
		or maxi(ay, by) < mini(cy, dy)
		or maxi(cy, dy) < mini(ay, by)
	):
		return false
	var c_side := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
	var d_side := (bx - ax) * (dy - ay) - (by - ay) * (dx - ax)
	if (c_side > 0 and d_side > 0) or (c_side < 0 and d_side < 0):
		return false
	var a_side := (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx)
	var b_side := (dx - cx) * (by - cy) - (dy - cy) * (bx - cx)
	return not ((a_side > 0 and b_side > 0) or (a_side < 0 and b_side < 0))
