extends RefCounted
## Integer behavior shared by the registered actor family.

const World = preload("res://src/sim/world.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const Damage = preload("res://src/sim/damage.gd")
const S := 3600
const ACTIVE := 1
const DEFEATED := 3


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
	if enemy.vx != 0:
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
		var distance: int = enemy.vx
		if (
			Motion.move(enemy, world, Motion.box(enemy, "e3"), distance, true) != distance
			or enemy.vx == 0
		):
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


static func contact_entity(
	enemy: Dictionary, state: Dictionary, _world: Dictionary, input: int
) -> void:
	if state.captured_by or enemy.status != ACTIVE:
		return
	var code: String = enemy.code
	if code == "e5":
		Plant.capture(enemy, enemy.family_index, state)
		if state.captured_by:
			return
		return
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
