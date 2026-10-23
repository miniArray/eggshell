class_name ScreenPlan
extends RefCounted
## Reference area policy from the brief; the actual container is the only input.


static func plan(container: Vector2, level_size: Vector2, focus: Vector2) -> Dictionary:
	var scale := sqrt(container.x * container.y / (832.0 * 448.0))
	scale = maxf(scale, maxf(container.x / level_size.x, container.y / level_size.y))
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
		"offset": container / 2.0 - center * scale
	}
