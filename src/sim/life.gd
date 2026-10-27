extends RefCounted
## Integration stub. The lifetime owner replaces these declarations and hooks.

const PLAYER_FIELDS := [
	["hurt", 0], ["invulnerable", 0], ["health", 10], ["health_wait", 0],
	["separated", 0], ["recovery_x", 0], ["recovery_y", 0],
	["recovery_delay", 0], ["hits", 0], ["hurt_deceleration", 0]
]
const LEVEL_FIELDS := []


static func touch_goal(state: Dictionary, _entity: Dictionary) -> void:
	state.goal_reached = 1


static func touch_checkpoint(_state: Dictionary, _entity: Dictionary) -> void:
	pass
