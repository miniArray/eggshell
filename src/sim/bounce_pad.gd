extends RefCounted
## Contact and movement math for one registered pad.

const Collision = preload("res://src/sim/collision.gd")
const S := 3600


static func advance_entity(ball: Dictionary, world: Dictionary) -> void:
	if not ball.active:
		return
	if ball.squash:
		ball.squash -= 1
		return
	var half_width: int = (22 if ball.large else 14) * S
	var height: int = (46 if ball.large else 30) * S
	var bounds := [-half_width, -height, half_width, 0]
	if not Collision.prepare(ball, world, bounds):
		ball.vy = 0
		return
	var support := Collision.track_floor(ball, world, bounds)
	if support != 0:
		ball.vy = 0
		return
	ball.vy = mini(ball.vy + 2048, 704 * 60)
	var distance: int = ball.vy
	var actual := Collision.vertical(ball, world, bounds, distance)
	if actual != distance:
		ball.vy = 0


static func contact_entity(ball: Dictionary, state: Dictionary, input: int) -> void:
	var half_width: int = (22 if ball.large else 14) * S
	var height: int = (46 if ball.large else 30) * S
	if (
		ball.active
		and state.vy > ball.vy
		and state.y < ball.y
		and state.y > ball.y - height
		and absi(state.x - ball.x) < half_width + 12 * S
	):
		state.vy = (-1216 - 544 * ball.large if input & 4 else -384 - 185 * ball.large) * 60
		state.on_floor = 0
		state.jump_buffer = 0
		state.flutter_remaining = 0
		state.flutter_ready = 1
		ball.squash = 12
		if ball.single_use:
			ball.active = 0
