extends SceneTree

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Damage = preload("res://src/sim/damage.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Collision = preload("res://src/level/collision_table.gd")
const S := State.SCALE
var assertions := 0
var failures := 0


func _initialize() -> void:
	var world: Dictionary = Fixtures.world()
	for example: Array in [
		[400, 1, -656, 164],
		[-400, 1, 144, -112],
		[-400, -1, 656, -164],
		[400, -1, -144, 112],
		[0, 1, -256, 112],
		[0, -1, 256, -112],
		[-256, 1, 0, 112],
		[192, 1, -448, 112],
		[-192, -1, 448, -112]
	]:
		var state := State.create(world)
		state.vx = example[0] * 60
		Damage.hurt(state, state.x + example[1] * S)
		check(state.vx == example[2] * 60, "post-knockback velocity: %s" % [example])
		check(state.companion_dx == example[3] * S, "separation sign/size: %s" % [example])
		check(
			state.recovery_y == state.y - 24 * S and state.recovery_delay == 36,
			"Launch starts at the attached companion anchor"
		)
	for velocity: int in [-800, 800, 0]:
		var state := State.create(world)
		Damage.separate(state, velocity * 60)
		var expected := 112 if velocity == 0 else -velocity / 4
		check(
			state.companion_dx == expected * S, "Zero is clamped positive; no upper magnitude cap"
		)
	for facing: int in [-1, 1]:
		var state := State.create(world)
		state.swimming = 1
		state.facing = facing
		state.vx = 400 * 60
		Damage.hurt(state, state.x + S)
		check(
			state.vx == -facing * 200 * 60 and state.companion_dx == facing * 112 * S,
			"Swimming separation uses its final knockback"
		)
	var separated := State.create(world)
	separated.vx = 400 * 60
	Damage.hurt(separated, separated.x + S)
	var marker_x: int = separated.recovery_x
	separated.invulnerable = 0
	separated.health_wait = 42
	Damage.hurt(separated, separated.x - S)
	check(
		separated.recovery_x == marker_x and separated.health_wait == 42,
		"Second hurt does not move marker or restart countdown"
	)
	print("DAMAGE_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
