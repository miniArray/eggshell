extends RefCounted

const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const S := State.SCALE


static func advance(state: Dictionary, world: Dictionary) -> void:
	for index in state.springs.size():
		var ball: Dictionary = state.springs[index]
		if not ball.active:
			continue
		if ball.squash:
			ball.squash -= 1
			continue
		ball.vy = mini(ball.vy + 2048, 704 * 60)
		var half_width: int = (22 if world.springs[index].large else 14) * S
		var height: int = (46 if world.springs[index].large else 30) * S
		var distance: int = ball.vy
		if World.overlaps_box(
			world,
			ball.x - half_width,
			ball.y + distance - height,
			ball.x + half_width,
			ball.y + distance
		):
			var low := 0
			var high := absi(distance)
			var signum := 1 if distance > 0 else -1
			while low < high:
				var middle := (low + high + 1) / 2
				var y: int = ball.y + middle * signum
				if World.overlaps_box(
					world, ball.x - half_width, y - height, ball.x + half_width, y
				):
					high = middle - 1
				else:
					low = middle
			distance = low * signum
			ball.vy = 0
		ball.y += distance


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
