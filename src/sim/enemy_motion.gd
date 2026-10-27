extends RefCounted
## Integer actor movement and periodic math. No engine physics.

const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/sim/collision.gd")
const S := 3600


static func random_ticks(state: Dictionary, low: int, high: int) -> int:
	state.rng = (state.rng * 1103515245 + 12345) & 0x7fffffff
	return low + (state.rng * (high - low) + 2147483647) / 2147483648


static func random_cycles(state: Dictionary) -> int:
	state.rng = (state.rng * 1103515245 + 12345) & 0x7fffffff
	return 1 + (state.rng * 3 + 1073741824) / 2147483648


static func sine(phase: int, period: int, amplitude: int) -> int:
	# Bhaskara rational approximation, exact at zero and extrema; no float sin().
	var half := period / 2
	var tick := phase % period
	var signum := 1 if tick < half else -1
	var x := tick % half
	var product := x * (half - x)
	return signum * amplitude * 16 * product / (5 * half * half - 4 * product)


static func root(value: int) -> int:
	var low := 0
	var high := mini(value, 1000000000)
	while low < high:
		var middle := (low + high + 1) / 2
		if middle <= value / middle:
			low = middle
		else:
			high = middle - 1
	return low


static func box(enemy: Dictionary, code: String) -> Array:
	match code:
		"e1":
			return [-10 * S, -18 * S, 10 * S, 16 * S]
		"e2":
			return (
				[-12 * S, -16 * S, 8 * S, 22 * S]
				if enemy.facing < 0
				else [-8 * S, -16 * S, 12 * S, 22 * S]
			)
		"e3":
			return [-14 * S, -34 * S, 14 * S, 16 * S]
		"e5":
			return [-14 * S, (-14 if enemy.mode == 0 else -10) * S, 14 * S, 16 * S]
		_:
			if enemy.mode == 2:
				return [-14 * S, -12 * S, 14 * S, 16 * S]
			if enemy.mode == 3:
				return [-14 * S, -14 * S, 14 * S, 14 * S]
			return (
				[-12 * S, -16 * S, 24 * S, 14 * S]
				if enemy.facing < 0
				else [-24 * S, -16 * S, 12 * S, 14 * S]
			)


static func overlaps(enemy: Dictionary, world: Dictionary, bounds: Array, dx: int, dy: int) -> bool:
	return World.overlaps_box(
		world,
		enemy.x + bounds[0] + dx,
		enemy.y + bounds[1] + dy,
		enemy.x + bounds[2] + dx,
		enemy.y + bounds[3] + dy
	)


static func move(
	enemy: Dictionary, world: Dictionary, bounds: Array, distance: int, horizontal: bool
) -> int:
	if not Collision.prepare(enemy, world, bounds):
		return 0
	var support := Collision.floor_at(enemy, world, bounds)
	if horizontal:
		return Collision.horizontal(enemy, world, bounds, distance, support, false, 640 * 60)
	return Collision.vertical(enemy, world, bounds, distance, support)


static func gravity(enemy: Dictionary, world: Dictionary, code: String) -> bool:
	var bounds := box(enemy, code)
	if not Collision.prepare(enemy, world, bounds):
		enemy.vy = 0
		return false
	var support := Collision.track_floor(enemy, world, bounds)
	if support != 0 and enemy.vy >= 0:
		enemy.vy = 0
		return true
	enemy.vy = mini(enemy.vy + 2048, 704 * 60)
	var distance: int = enemy.vy
	var actual := Collision.vertical(enemy, world, bounds, distance, support)
	var landed := (
		distance >= 0 and (actual != distance or Collision.floor_at(enemy, world, bounds) != 0)
	)
	if landed or actual != distance:
		enemy.vy = 0
	return landed


static func edge(enemy: Dictionary, world: Dictionary, bounds: Array) -> bool:
	var left: int = enemy.x if enemy.facing > 0 else enemy.x - 12 * S
	var right: int = left + 12 * S
	var bottom: int = enemy.y + bounds[3]
	if World.overlaps_box(world, left, bottom, right, bottom + 28 * S):
		return false
	for bridge: Dictionary in world.bridges:
		if (
			bottom <= bridge.top
			and bottom + 28 * S > bridge.top
			and left < bridge.right
			and right > bridge.left
		):
			return false
	return true
