extends RefCounted

const State = preload("res://src/sim/play_state.gd")
const Collision = preload("res://src/sim/collision.gd")
const S := State.SCALE


static func advance(state: Dictionary, world: Dictionary) -> void:
	for index in state.springs.size():
		var ball: Dictionary = state.springs[index]
		if not ball.active:
			continue
		if ball.squash:
			ball.squash -= 1
			continue
		var half_width: int = (22 if world.springs[index].large else 14) * S
		var height: int = (46 if world.springs[index].large else 30) * S
		var bounds := [-half_width, -height, half_width, 0]
		if not Collision.prepare(ball, world, bounds):
			ball.vy = 0
			continue
		var support := Collision.track_floor(ball, world, bounds)
		if support != 0:
			ball.vy = 0
			continue
		ball.vy = mini(ball.vy + 2048, 704 * 60)
		var distance: int = ball.vy
		var actual := Collision.vertical(ball, world, bounds, distance)
		if actual != distance:
			ball.vy = 0


static func contact(state: Dictionary, input: int, world: Dictionary) -> void:
	for index in state.springs.size():
		var ball: Dictionary = state.springs[index]
		var source: Dictionary = world.springs[index]
		var half_width: int = (22 if source.large else 14) * S
		var height: int = (46 if source.large else 30) * S
		if (
			ball.active
			and state.vy > ball.vy
			and state.y < ball.y
			and state.y > ball.y - height
			and absi(state.x - ball.x) < half_width + 12 * S
		):
			state.vy = (-1216 - 544 * source.large if input & 4 else -384 - 185 * source.large) * 60
			state.on_floor = 0
			state.jump_buffer = 0
			state.flutter_remaining = 0
			state.flutter_ready = 1
			ball.squash = 12
			if source.single_use:
				ball.active = 0
