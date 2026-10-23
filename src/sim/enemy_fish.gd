extends RefCounted

const Motion = preload("res://src/sim/enemy_motion.gd")
const World = preload("res://src/sim/world.gd")
const S := 3600


static func advance(
	enemy: Dictionary, source: Dictionary, state: Dictionary, world: Dictionary
) -> void:
	var deep := World.water_at(world, enemy.x, enemy.y - 8 * S)
	var origin_wet := World.water_at(world, enemy.x, enemy.y)
	var bounds := Motion.box(enemy, "e20")
	var wet := World.water_overlaps(
		world, enemy.x + bounds[0], enemy.y + bounds[1], enemy.x + bounds[2], enemy.y + bounds[3]
	)
	if enemy.mode == 3:
		enemy.vy = mini(enemy.vy + 2048, 704 * 60)
		enemy.x += enemy.vx
		enemy.y += enemy.vy
		if origin_wet and enemy.vy > 0:
			enemy.mode = 0
			enemy.phase = 0
			enemy.vx = enemy.facing * 128 * 60
			enemy.cycles = Motion.random_ticks(state, 60, 180)
		return
	if enemy.mode == 2:
		enemy.timer -= 1
		if enemy.timer == 0:
			enemy.vy = -944 * 60
			enemy.mode = 3
		return
	if not wet:
		enemy.water = 0
		enemy.vy = mini(enemy.vy + 2048, 704 * 60)
		enemy.y += enemy.vy
		return
	if deep:
		if enemy.rise_ticks:
			enemy.rise_ticks -= 1
			enemy.vy = enemy.rise_velocity * enemy.rise_ticks * enemy.rise_ticks / 3600
		else:
			enemy.vy -= 384
			if enemy.vy > 0:
				enemy.rise_ticks = 60
				enemy.rise_velocity = enemy.vy / 6
				enemy.vy = enemy.rise_velocity
		if enemy.water:
			enemy.home_y += enemy.vy
		else:
			enemy.y += enemy.vy
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
		enemy.y = enemy.home_y + Motion.sine(enemy.phase, 60, 6 * S)
	if enemy.mode == 1:
		enemy.timer -= 1
		enemy.vx = approach(enemy.vx, 0, 512)
		if enemy.timer == 0:
			enemy.facing *= -1
			enemy.mode = 0
	else:
		enemy.vx = approach(enemy.vx, enemy.facing * 128 * 60, 512)
		if (
			(enemy.x < source.x - 48 * S and enemy.facing < 0)
			or (enemy.x > source.x + 48 * S and enemy.facing > 0)
		):
			enemy.mode = 1
			enemy.timer = 33  # 0.15s delay + 0.4s turn animation.
		if source.variant == 1 and enemy.water:
			if not enemy.cycles:
				enemy.cycles = Motion.random_ticks(state, 60, 180)
			enemy.cycles -= 1
			if enemy.cycles == 0:
				enemy.mode = 2
				enemy.water = 0
				enemy.timer = 10
				enemy.vx = 0
	enemy.x += enemy.vx


static func approach(value: int, target: int, amount: int) -> int:
	return mini(value + amount, target) if value < target else maxi(value - amount, target)
