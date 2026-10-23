extends RefCounted

const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Fish = preload("res://src/sim/enemy_fish.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const Damage = preload("res://src/sim/damage.gd")
const S := 3600
const WAITING := 0
const ACTIVE := 1
const QUEUED := 2
const DEFEATED := 3


static func advance(state: Dictionary, world: Dictionary, pressed: int) -> void:
	for index in state.enemies.size():
		var enemy: Dictionary = state.enemies[index]
		var source: Dictionary = world.enemies[index]
		lifecycle(enemy, source, state)
		if enemy.status != ACTIVE:
			continue
		match source.code:
			"e1":
				walker(enemy, state, world)
			"e2":
				flyer(enemy, source, world)
			"e3":
				flower(enemy, world)
			"e5":
				Plant.advance(enemy, state, world, pressed)
			"e20":
				Fish.advance(enemy, source, state, world)


static func lifecycle(enemy: Dictionary, source: Dictionary, state: Dictionary) -> void:
	if enemy.status == DEFEATED:
		return
	if enemy.status == ACTIVE:
		if absi(enemy.x - state.camera_x) > 832 * S or absi(enemy.y - state.camera_y) > 832 * S:
			enemy.status = QUEUED
			enemy.offscreen = 0
	if enemy.status == QUEUED:
		if absi(source.x - state.camera_x) > 416 * S or absi(source.y - state.camera_y) > 224 * S:
			enemy.offscreen = 1
		if (
			enemy.offscreen
			and absi(source.x - state.camera_x) < 624 * S
			and absi(source.y - state.camera_y) < 624 * S
		):
			var fresh := State.enemy_create(source)
			for field: String in State.ENEMY_FIELDS:
				enemy[field] = fresh[field]
	if enemy.status == WAITING:
		var bounds := Motion.box(enemy, source.code)
		if (
			enemy.x + bounds[2] > state.camera_x - 416 * S
			and enemy.x + bounds[0] < state.camera_x + 416 * S
			and enemy.y + bounds[3] > state.camera_y - 224 * S
			and enemy.y + bounds[1] < state.camera_y + 224 * S
		):
			enemy.status = ACTIVE
			if source.mirror == 2:
				enemy.facing = -1 if state.x < enemy.x else 1
			if source.code == "e2":
				enemy.cycles = 1 if enemy.facing < 0 else -1
			if source.code == "e1":
				enemy.timer = Motion.random_ticks(state, 60, 150)
				enemy.cycles = Motion.random_cycles(state)


static func walker(enemy: Dictionary, state: Dictionary, world: Dictionary) -> void:
	enemy.timer -= 1
	if enemy.mode == 0:
		enemy.phase += 1
		if enemy.phase % 30 == 0:
			enemy.facing *= -1
		if enemy.timer == 0:
			enemy.mode = 1
			enemy.timer = 15
	else:
		if enemy.timer == 0:
			if enemy.cycles:
				enemy.cycles -= 1
				enemy.timer = 15
			else:
				enemy.mode = 0
				enemy.phase = 0
				enemy.timer = Motion.random_ticks(state, 60, 150)
				enemy.cycles = Motion.random_cycles(state)
	enemy.vx = enemy.facing * 48 * 60 if enemy.mode == 1 else 0
	Motion.move(enemy, world, Motion.box(enemy, "e1"), enemy.vx, true)
	if (
		Motion.gravity(enemy, world, "e1")
		and enemy.mode == 1
		and Motion.edge(enemy, world, Motion.box(enemy, "e1"))
	):
		enemy.facing *= -1


static func flyer(enemy: Dictionary, source: Dictionary, world: Dictionary) -> void:
	enemy.phase = (enemy.phase + 1) % 360
	var leg: int = enemy.phase if enemy.phase <= 180 else 360 - enemy.phase
	enemy.vx = (-128 * 60 + 256 * 60 * leg / 180) * enemy.cycles
	Motion.move(enemy, world, Motion.box(enemy, "e2"), enemy.vx, true)
	enemy.facing = 1 if enemy.vx > 0 else -1
	enemy.y = source.y + Motion.sine(enemy.phase, 180, 12 * S)


static func flower(enemy: Dictionary, world: Dictionary) -> void:
	if enemy.mode == 1:
		enemy.timer -= 1
		if enemy.timer in [72, 54, 36]:
			enemy.facing *= -1
		if enemy.timer == 0:
			enemy.mode = 0
	enemy.vx = 0
	if enemy.mode == 0:
		var speed := 24 if World.water_at(world, enemy.x, enemy.y) else 48
		enemy.vx = enemy.facing * speed * 60
		if Motion.move(enemy, world, Motion.box(enemy, "e3"), enemy.vx, true) != enemy.vx:
			enemy.mode = 1
			enemy.timer = 108
			enemy.vx = 0
	if (
		Motion.gravity(enemy, world, "e3")
		and enemy.mode == 0
		and Motion.edge(enemy, world, Motion.box(enemy, "e3"))
	):
		enemy.mode = 1
		enemy.timer = 108
		enemy.vx = 0


static func contact(state: Dictionary, input: int, world: Dictionary) -> void:
	if state.captured_by:
		return
	for index in state.enemies.size():
		var enemy: Dictionary = state.enemies[index]
		var code: String = world.enemies[index].code
		if enemy.status != ACTIVE:
			continue
		if code == "e5":
			Plant.capture(enemy, index, state)
			if state.captured_by:
				return
			continue
		var bounds := Motion.box(enemy, code)
		var overlap: bool = (
			state.x + 12 * S > enemy.x + bounds[0]
			and state.x - 12 * S < enemy.x + bounds[2]
			and state.y > enemy.y + bounds[1]
			and state.y - 56 * S < enemy.y + bounds[3]
		)
		if overlap:
			if enemy.y > state.y - 8 * S and not enemy.contact:
				state.vy = -absi(enemy.vy / 2) - (704 if input & 4 else 320) * 60
				state.on_floor = 0
				state.jump_buffer = 0
				state.flutter_remaining = 0
				state.boosted_flutter = 1
				state.flutter_ready = 1
				enemy.status = DEFEATED
			elif enemy.y < state.y - 8 * S:
				Damage.hurt(state, enemy.x)
			enemy.contact = 1
		else:
			enemy.contact = 0
