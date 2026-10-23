class_name PlayState
extends RefCounted
## All mutable play facts. Positions and velocities use 1/3600 px units per tick.

const SCALE := 3600
const FIELDS := [
	"frame",
	"x",
	"y",
	"vx",
	"vy",
	"movement",
	"facing",
	"on_floor",
	"camera_x",
	"camera_y",
	"goal_reached",
	"previous_input",
	"jump_buffer",
	"deaths",
	"flutter_remaining",
	"flutter_cooldown",
	"flutter_ready",
	"support_bridge",
	"swimming",
	"water_wait",
	"water_phase",
	"water_deep",
	"boosted_flutter",
	"hurt",
	"invulnerable",
	"health",
	"health_wait",
	"separated",
	"recovery_x",
	"recovery_y",
	"recovery_delay",
	"hits",
	"captured_by",
	"hurt_deceleration",
	"rng"
]

const ENEMY_FIELDS := [
	"x",
	"y",
	"vx",
	"vy",
	"facing",
	"status",
	"phase",
	"timer",
	"cycles",
	"mode",
	"home_y",
	"water",
	"contact",
	"offscreen",
	"head_dx",
	"head_dy",
	"head_size",
	"rise_ticks",
	"rise_velocity",
	"pin_size"
]


static func create(level: Dictionary) -> Dictionary:
	var state := {"identity": level.identity}
	for field: String in FIELDS:
		state[field] = 0
	state.springs = []
	for spring: Dictionary in level.springs:
		state.springs.append(
			{"x": spring.x, "y": spring.y, "vx": 0, "vy": 0, "squash": 0, "active": 1}
		)
	state.enemies = []
	for enemy: Dictionary in level.get("enemies", []):
		state.enemies.append(enemy_create(enemy))
	state.health = 10
	state.rng = 1  # Fixed seed; serialized with the play state.
	state.x = level.spawn_x
	state.y = level.spawn_y
	state.facing = 1
	state.camera_x = state.x
	# Follow the center of the documented 56px-tall collision box.
	state.camera_y = state.y - 28 * SCALE
	return state


static func enemy_create(source: Dictionary) -> Dictionary:
	var enemy := {}
	for field: String in ENEMY_FIELDS:
		enemy[field] = 0
	enemy.x = source.x
	enemy.y = source.y
	enemy.home_y = source.y
	enemy.facing = 1 if source.mirror == 1 else -1
	return enemy
