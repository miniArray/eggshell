extends RefCounted

const State = preload("res://src/sim/play_state.gd")
const S := 3600


static func separate(state: Dictionary, velocity_at_separation: int) -> void:
	if state.separated:
		return
	state.separated = 1
	state.health_wait = 45
	# Convert post-knockback speed to a recovery-point displacement.
	var displacement := -velocity_at_separation * 15
	# E591 includes zero (>= 0); E592 handles only negative displacement.
	displacement = (
		maxi(displacement, 112 * S) if displacement >= 0 else mini(displacement, -112 * S)
	)
	state.recovery_x = state.x + displacement
	state.recovery_y = state.y - 56 * S
	state.recovery_delay = 36


static func hurt(state: Dictionary, damager_x: int) -> void:
	if state.invulnerable or state.captured_by:
		return
	var already_separated: bool = state.separated == 1
	state.hits += 1
	state.invulnerable = 120
	state.hurt = 60 if already_separated else 36
	state.hurt_deceleration = 1296
	if state.swimming:
		state.vx = -state.facing * 200 * 60
	elif state.x < damager_x:
		state.vx = -state.vx - 256 * 60
	elif state.x > damager_x:
		state.vx = -state.vx + 256 * 60
	state.vy = -384 * 60
	separate(state, state.vx)
	state.on_floor = 0
	state.jump_buffer = 0
	state.flutter_remaining = 0


static func prepare(state: Dictionary) -> bool:
	state.invulnerable = maxi(0, state.invulnerable - 1)
	state.hurt = maxi(0, state.hurt - 1)
	state.recovery_delay = maxi(0, state.recovery_delay - 1)
	if state.separated:
		state.health_wait -= 1
		if state.health_wait == 0:
			state.health -= 1
			state.health_wait = 45
			return state.health == 0
	elif state.health < 10:
		state.health_wait -= 1
		if state.health_wait <= 0:
			state.health += 1
			state.health_wait = 120 if state.health < 10 else 0
	return false


static func recover(state: Dictionary) -> void:
	if state.separated and not state.recovery_delay and not state.captured_by:
		if (
			absi(state.x - state.recovery_x) < 12 * S
			and state.y > state.recovery_y
			and state.y - 56 * S < state.recovery_y
		):
			state.separated = 0
			state.health_wait = 120 if state.health < 10 else 0


static func respawn(state: Dictionary, world: Dictionary) -> void:
	state.x = world.spawn_x
	state.y = world.spawn_y
	state.camera_x = state.x
	state.camera_y = state.y - 28 * S
	state.vx = 0
	state.vy = 0
	state.on_floor = 0
	state.support_bridge = 0
	state.deaths += 1
	for field: String in [
		"flutter_remaining",
		"flutter_cooldown",
		"flutter_ready",
		"boosted_flutter",
		"swimming",
		"water_wait",
		"water_phase",
		"water_deep",
		"hurt",
		"invulnerable",
		"separated",
		"health_wait",
		"recovery_delay",
		"captured_by",
		"jump_buffer",
		"hurt_deceleration",
		"recovery_x",
		"recovery_y"
	]:
		state[field] = 0
	state.health = 10
	var fresh := State.create(world)
	state.enemies = fresh.enemies
	state.springs = fresh.springs
	state.rng = fresh.rng
