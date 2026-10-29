extends RefCounted
## Integer behavior shared by the registered actor family.

const World = preload("res://src/sim/world.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Plant = preload("res://src/sim/enemy_plant.gd")
const Damage = preload("res://src/sim/damage.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Hits = preload("res://src/sim/hits.gd")
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


## The horizontal swing starts when the flyer wakes; its vertical wave runs on the level
## clock from level load, so every flyer of a level bobs in phase.
static func flyer(enemy: Dictionary, source: Dictionary, world: Dictionary, frame: int) -> void:
	if enemy.phase == 0:
		# The swing starts one step after the first step: only the wave moves it now.
		enemy.phase = 360
		bob(enemy, source, frame)
		return
	enemy.phase = enemy.phase % 360 + 1
	var leg: int = enemy.phase if enemy.phase <= 180 else 360 - enemy.phase
	# The swing tweens the speed from -128 to 128 px/s; the body's 48 px/s top speed caps it.
	enemy.vx = clampi((-128 * 60 + 256 * 60 * leg / 180) * enemy.cycles, -48 * 60, 48 * 60)
	Motion.move(enemy, world, Motion.box(enemy, "e2"), enemy.vx, true)
	if enemy.vx != 0:
		enemy.facing = 1 if enemy.vx > 0 else -1
	bob(enemy, source, frame)


## The vertical wave alone, on the level clock.
static func bob(enemy: Dictionary, source: Dictionary, frame: int) -> void:
	enemy.y = source.y + Motion.sine((frame + Motion.LEVEL_INTRO_TICKS) % 180, 180, 12 * S)


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
	var overlap := Body.player_overlap(enemy, state, bounds)
	if overlap:
		if enemy.y > state.y - 8 * S and not enemy.contact:
			if not Body.pounding(state):
				Body.bounce(enemy, state, input)
			enemy.status = DEFEATED
		elif enemy.y < state.y - 8 * S:
			Damage.hurt(state, enemy.x)
		enemy.contact = 1
	else:
		enemy.contact = 0
