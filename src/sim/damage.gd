extends RefCounted
## Contact damage changes motion and separates the companion; it does not kill.

const Life = preload("res://src/sim/life.gd")
const Sound = preload("res://src/sim/sound_events.gd")


static func separate(state: Dictionary, velocity_at_separation: int) -> void:
	# Captures release the companion directly into a bubble.
	Life.separate(state, velocity_at_separation, true)


static func hurt(state: Dictionary, damager_x: int) -> void:
	Life.ensure_fields(state)
	if state.invulnerable or state.get("captured_by", 0) or state.life_phase != Life.PLAY:
		return
	var already_separated: bool = state.separated == 1
	state.invulnerable = 120
	Sound.player(state)
	if already_separated:
		Life.start_hurt(state, Life.SPIN_LOCK, false)
	else:
		# A first hit in water separates the companion without a knock-back pose.
		Life.start_hurt(state, 0 if state.swimming else Life.KNOCKED_LOCK, true)
	state.hurt_deceleration = 128 if state.swimming else 1296
	if state.swimming:
		state.vx = -state.facing * 200 * 60
	elif state.x < damager_x:
		state.vx = -state.vx - 256 * 60
	elif state.x > damager_x:
		state.vx = -state.vx + 256 * 60
	state.vy = -384 * 60
	Life.separate(state, state.vx)
	state.on_floor = 0
	state.jump_buffer = 0
	state.flutter_remaining = 0
