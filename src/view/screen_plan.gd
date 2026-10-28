class_name ScreenPlan
extends RefCounted
## Reference area policy from the brief; the actual container is the only input.
## Zoom is a whole-number step on the art-pixel multiple, clamped by the container.

## Zooming in stops before the view shows less than this many world pixels.
const MIN_VISIBLE := Vector2(208, 112)


static func plan(
	container: Vector2, level_size: Vector2, focus: Vector2, density: int = 1, zoom: int = 0
) -> Dictionary:
	var reference := sqrt(container.x * container.y / (832.0 * 448.0))
	reference /= density
	var k := maxi(1, floori(reference))
	# Equal ratio distances meet at the geometric mean of adjacent integers.
	if reference > sqrt(float(k) * (k + 1)):
		k += 1
	# The smallest multiple that keeps the view inside the level bounds.
	var fit := maxi(
		1,
		ceili(maxf(container.x / (level_size.x * density), container.y / (level_size.y * density)))
	)
	k = maxi(k, fit)
	var closest := floori(
		minf(container.x / (MIN_VISIBLE.x * density), container.y / (MIN_VISIBLE.y * density))
	)
	var largest := maxi(k, closest)
	var multiple := clampi(k + zoom, fit, largest)
	var scale := float(multiple * density)
	var visible := container / scale
	var half := visible / 2.0
	var center := Vector2(
		clampf(focus.x, half.x, level_size.x - half.x),
		clampf(focus.y, half.y, level_size.y - half.y)
	)
	return {
		"scale": scale,
		"center": center,
		"visible": visible,
		"offset": container / 2.0 - center * scale,
		"base_scale": float(k * density),
		"zoom": multiple - k,
		"zoom_min": fit - k,
		"zoom_max": largest - k
	}
