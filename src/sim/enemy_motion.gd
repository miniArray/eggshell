extends RefCounted
## Integer actor movement and periodic math. No engine physics.

const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/sim/collision.gd")
const S := 3600
# The registry is bound late to avoid an import cycle; load() once, not per probe.
static var _registry: Script = null


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
	if enemy.get("roll", 0) and code in ["e1", "e2"]:
		return [-12 * S, -12 * S, 12 * S, 16 * S]
	match code:
		"e1":
			return [-10 * S, -18 * S, 10 * S, 16 * S]
		"e2":
			if enemy.get("ground_form", 0):
				return [-10 * S, -18 * S, 10 * S, 16 * S]
			return (
				[-12 * S, -16 * S, 8 * S, 22 * S]
				if enemy.facing < 0
				else [-8 * S, -16 * S, 12 * S, 22 * S]
			)
		"e3":
			return [-14 * S, -34 * S, 14 * S, 16 * S]
		"e5":
			var top := (-14 if enemy.mode == 0 else -10) * S
			if enemy.get("variant", 0) == 1:
				return [-14 * S, -16 * S, 14 * S, -top]  # Hanging stem: flipped vertically.
			return [-14 * S, top, 14 * S, 16 * S]
		"e20", "e21":
			if enemy.mode == 2:
				return [-14 * S, -12 * S, 14 * S, 16 * S]
			if enemy.mode == 3:
				return [-14 * S, -14 * S, 14 * S, 14 * S]
			return (
				[-12 * S, -16 * S, 24 * S, 14 * S]
				if enemy.facing < 0
				else [-24 * S, -16 * S, 12 * S, 14 * S]
			)
		_:
			if _registry == null:
				_registry = load("res://src/sim/registry.gd")
			var type: Script = _registry.lookup(code)
			return (
				type.bounds(enemy)
				if type.has_method("bounds")
				else [-16 * S, -16 * S, 16 * S, 16 * S]
			)


static func turn_sine(angle: int, amplitude: int = S) -> int:
	return sine(posmod(angle, 360000), 360000, amplitude)


static func turn_cosine(angle: int, amplitude: int = S) -> int:
	return turn_sine(angle + 90000, amplitude)


static func angle_to(dx: int, dy: int) -> int:
	if dx == 0 and dy == 0:
		return 270000
	var largest := maxi(absi(dx), absi(dy))
	var x := absi(dx) * 1000000 / largest
	var y := absi(dy) * 1000000 / largest
	var low := 0
	var high := 90000
	while high - low > 1:
		var middle := (high + low) / 2
		if turn_sine(middle) * x < turn_cosine(middle) * y:
			low = middle
		else:
			high = middle
	var angle := (high + low) / 2
	if dx < 0:
		angle = 180000 - angle
	if dy < 0:
		angle = 360000 - angle
	return posmod(angle, 360000)


static func angle_delta(from: int, to: int) -> int:
	return posmod(to - from + 180000, 360000) - 180000


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
	return gravity_box(enemy, world, box(enemy, code))


static func gravity_box(
	enemy: Dictionary,
	world: Dictionary,
	bounds: Array,
	acceleration: int = 2048,
	cap: int = 704 * 60
) -> bool:
	if not Collision.prepare(enemy, world, bounds):
		enemy.vy = 0
		return false
	if (
		enemy.get("code", "") not in ["e20", "e21"]
		and World.water_overlaps(
			world,
			enemy.x + bounds[0],
			enemy.y + bounds[1],
			enemy.x + bounds[2],
			enemy.y + bounds[3]
		)
	):
		acceleration = (2048 if enemy.get("code", "") == "enemy_spike" else acceleration) / 4
		cap /= 4
	var support := Collision.track_floor(enemy, world, bounds)
	if support != 0 and enemy.vy >= 0:
		enemy.vy = 0
		return true
	# Platform order: move by the mean of this step's old and new speed (only when the
	# body already moves), then add gravity unless the step started on a floor.
	var distance: int = mini(enemy.vy + acceleration / 2, cap) if enemy.vy else 0
	var actual := Collision.vertical(enemy, world, bounds, distance, support)
	var landed := (
		distance >= 0 and (actual != distance or Collision.floor_at(enemy, world, bounds) != 0)
	)
	if landed or actual != distance:
		enemy.vy = 0
	if not landed and support == 0:
		enemy.vy = mini(enemy.vy + acceleration, cap)
	return landed


static func edge(enemy: Dictionary, world: Dictionary, bounds: Array) -> bool:
	var left: int = enemy.x if enemy.facing > 0 else enemy.x - 12 * S
	var right: int = left + 12 * S
	var bottom: int = enemy.y + bounds[3]
	return not Collision.support_in_box(world, left, bottom, right, bottom + 28 * S, enemy)
