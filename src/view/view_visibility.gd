extends RefCounted
## Pure presentation policy. A null envelope means unproven: never reject it.
## The camera uses the rounded translation actually submitted to the renderer.
const MARGIN := 2.0


static func camera(viewport: Vector2, offset: Vector2, scale: float) -> Rect2:
	return Rect2(-offset / scale, viewport / scale).grow(MARGIN)


static func needed(envelope: Variant, origin: Vector2, camera_rect: Rect2) -> bool:
	if not envelope is Rect2:
		return true
	var bounds: Rect2 = envelope
	return camera_rect.intersects(Rect2(bounds.position + origin, bounds.size), true)


## Rotation- and mirror-independent envelope for a rectangle about its origin.
static func radial(rect: Rect2) -> Rect2:
	var extent := rect.position.abs().max(rect.end.abs())
	var radius := extent.length()
	return Rect2(Vector2(-radius, -radius), Vector2.ONE * radius * 2)
