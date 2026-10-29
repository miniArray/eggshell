extends RefCounted
## Water patrol, vertical jumps, arcs and dry-ground movement.

const Motion = preload("res://src/sim/enemy_motion.gd")
const World = preload("res://src/sim/world.gd")
const S := 3600
## A turn: the 0.15 s wait and the 0.4 s turn picture (33 ticks), plus one tick each way
## because a simulated control press reaches the Platform movement on the next tick.
const TURN_TICKS := 35


static func advance(
	enemy: Dictionary, source: Dictionary, state: Dictionary, world: Dictionary
) -> void:
	if enemy.fish_exhausted:
		return
	if enemy.fish_finish:
		enemy.fish_finish -= 1
		if enemy.fish_finish == 0:
			enemy.fish_exhausted = 1
			enemy.hidden = 1
			enemy.vx = 0
			enemy.vy = 0
			return
	var deep := World.water_at(world, enemy.x, enemy.y - 8 * S)
	var origin_wet := World.water_at(world, enemy.x, enemy.y)
	var bounds := Motion.box(enemy, enemy.code)
	var wet := World.water_overlaps(
		world, enemy.x + bounds[0], enemy.y + bounds[1], enemy.x + bounds[2], enemy.y + bounds[3]
	)
	if enemy.mode in [3, 4]:
		enemy.vy = mini(enemy.vy + 2048, 704 * 60)
		var falling: bool = enemy.vy > 0
		_translate(enemy, world, bounds, enemy.vx, enemy.vy)
		if origin_wet and falling:
			enemy.mode = 0
			enemy.phase = 0
			enemy.vx = enemy.facing * 128 * 60
			if enemy.variant == 1:
				enemy.cycles = Motion.random_ticks(state, 60, 180)
			else:
				enemy.rise_ticks = 3
				enemy.rise_duration = 3
				enemy.rise_velocity = enemy.vy / 4
				if enemy.variant == 3 and enemy.fish_jumps == 0:
					enemy.fish_finish = 3
		return
	if enemy.mode == 2:
		enemy.timer -= 1
		if enemy.timer == 0:
			enemy.vy = -944 * 60
			enemy.mode = 3
		return
	if not wet:
		enemy.water = 0
		enemy.vx = enemy.facing * 128 * 60 if enemy.fish_dry else 0
		if enemy.code == "e21":
			_translate(enemy, world, bounds, enemy.vx, 0)
			if Motion.gravity_box(enemy, world, bounds):
				enemy.fish_dry = 1
				_flop(enemy, state)
		else:
			enemy.vy = mini(enemy.vy + 2048, 704 * 60)
			enemy.x += enemy.vx
			enemy.y += enemy.vy
		return
	enemy.fish_dry = 0
	if deep:
		if enemy.rise_ticks:
			enemy.rise_ticks -= 1
			var duration: int = enemy.rise_duration
			enemy.vy = (
				enemy.rise_velocity * enemy.rise_ticks * enemy.rise_ticks / (duration * duration)
			)
		else:
			enemy.vy -= 384
			if enemy.vy > 0:
				enemy.rise_ticks = 60
				enemy.rise_duration = 60
				enemy.rise_velocity = enemy.vy / 6
				enemy.vy = enemy.rise_velocity
		if enemy.water:
			enemy.home_y += enemy.vy
		else:
			_translate(enemy, world, bounds, 0, enemy.vy)
	else:
		if enemy.vy <= 0:
			enemy.vy = 0
		if not enemy.water:
			enemy.water = 1
			enemy.home_y = enemy.y
			enemy.phase = 0
		enemy.home_y += enemy.vy
	if enemy.water:
		enemy.phase = (enemy.phase + 1) % 60
		var next_y: int = enemy.home_y + Motion.sine(enemy.phase, 60, 6 * S)
		_translate(enemy, world, bounds, 0, next_y - enemy.y)
	# Platform order: an accelerating body moves by the mean of its old and new speed
	# (only when it already moves); a braking body moves by its old speed.
	var braking: bool = enemy.mode == 1 and enemy.timer < TURN_TICKS
	var old_vx: int = enemy.vx
	if enemy.mode == 1:
		enemy.timer -= 1
		# The last control press still accelerates on the turn's first tick.
		var target: int = 0 if braking else enemy.facing * 128 * 60
		enemy.vx = approach(enemy.vx, target, 512)
		if enemy.timer == 0:
			enemy.facing *= -1
			enemy.mode = 0
			enemy.fish_ready = 1
	else:
		enemy.vx = approach(enemy.vx, enemy.facing * 128 * 60, 512)
		if (
			enemy.variant <= 2
			and (
				(enemy.x < enemy.home_x - enemy.fish_left and enemy.facing < 0)
				or (enemy.x > enemy.home_x + enemy.fish_right and enemy.facing > 0)
			)
		):
			enemy.mode = 1
			enemy.timer = TURN_TICKS
		if source.variant == 1 and enemy.water:
			if not enemy.cycles:
				enemy.cycles = Motion.random_ticks(state, 60, 180)
			enemy.cycles -= 1
			if enemy.cycles == 0:
				enemy.mode = 2
				enemy.water = 0
				enemy.timer = 10
				enemy.vx = 0
		elif enemy.variant >= 2 and enemy.water and enemy.fish_ready:
			var jump: bool = enemy.variant == 3 and enemy.fish_jumps > 0
			if enemy.variant == 2:
				if enemy.facing < 0:
					jump = enemy.x < enemy.home_x + (-64 if enemy.fish_left > 0 else 192) * S
				else:
					jump = enemy.x > enemy.home_x + (-192 if enemy.fish_left > 0 else 64) * S
			if jump:
				enemy.mode = 4
				enemy.water = 0
				enemy.vy = -800 * 60
				enemy.vx = enemy.facing * 128 * 60
				if enemy.variant == 2:
					enemy.fish_ready = 0
				else:
					enemy.fish_jumps -= 1
	var dx: int = enemy.vx
	if braking:
		dx = old_vx
	elif enemy.mode in [0, 1]:
		dx = (old_vx + enemy.vx) / 2 if old_vx else 0
	_translate(enemy, world, bounds, dx, 0)


static func _translate(
	enemy: Dictionary, world: Dictionary, bounds: Array, dx: int, dy: int
) -> void:
	if enemy.code == "e20":
		enemy.x += dx
		enemy.y += dy
		return
	if dx:
		var actual := Motion.move(enemy, world, bounds, dx, true)
		if actual != dx:
			if enemy.mode in [3, 4]:
				enemy.vx = -dx
			elif enemy.mode != 1:
				if enemy.variant <= 1:
					enemy.home_x = enemy.x - enemy.facing * 64 * S
				elif enemy.variant == 2:
					enemy.home_x = enemy.x - enemy.facing * 128 * S
					enemy.fish_left = (-24 if enemy.facing < 0 else 232) * S
					enemy.fish_right = (232 if enemy.facing < 0 else -24) * S
				enemy.mode = 1
				enemy.timer = TURN_TICKS
	if dy:
		var actual := Motion.move(enemy, world, bounds, dy, false)
		if actual != dy:
			enemy.vy = 0


static func _flop(enemy: Dictionary, state: Dictionary) -> void:
	enemy.facing = 1 if Motion.random_ticks(state, 0, 2) == 1 else -1
	enemy.vy = (-256 if Motion.random_ticks(state, 0, 2) == 1 else -384) * 60


static func approach(value: int, target: int, amount: int) -> int:
	return mini(value + amount, target) if value < target else maxi(value - amount, target)
