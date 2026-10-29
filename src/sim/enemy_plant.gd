extends RefCounted

const Motion = preload("res://src/sim/enemy_motion.gd")
const Collision = preload("res://src/sim/collision.gd")
const Damage = preload("res://src/sim/damage.gd")
const Life = preload("res://src/sim/life.gd")
const S := 3600
const CHEW_REACH := 44  # Head anchor reach relative to the stem origin.
const HEAD := [50, 22, 30, 34, 8, 26, -2, 8, 8, -10, 30, -20, 50, -8, 62, 8]
const HANGING := 1  # Placement form F=1: the stem hangs from the ceiling.


## The hanging form flips the stem and pins it to a solid just above it. Without one,
## it becomes the ground form for the rest of this spawn.
static func attach(enemy: Dictionary, world: Dictionary) -> void:
	if not Collision.overlaps(enemy, world, Motion.box(enemy, "e5"), 0, -4 * S):
		enemy.variant = 0


static func hanging(enemy: Dictionary) -> bool:
	return enemy.variant == HANGING


static func pivot_y(enemy: Dictionary) -> int:
	return enemy.y + (10 if hanging(enemy) else -10) * S


static func advance(enemy: Dictionary, state: Dictionary, world: Dictionary, pressed: int) -> void:
	if hanging(enemy):
		enemy.vy = 0  # Pinned to the ceiling; no gravity.
	else:
		Motion.gravity(enemy, world, "e5")
	if enemy.mode == 4:
		enemy.head_size = mini(15, enemy.head_size + 1)
		enemy.phase += 1
		enemy.timer -= 1
		if enemy.phase == 30:
			Damage.separate(state, -enemy.facing * 400 * 60)
		if enemy.phase > 60 and pressed & 4:
			enemy.timer = maxi(0, enemy.timer - 30)
		if enemy.timer == 0:
			release(enemy, state)
		else:
			pin_player(enemy, state)
		return
	if enemy.mode == 5:
		enemy.timer -= 1
		if enemy.timer == 0:
			enemy.mode = 2
		return
	var near: bool = absi(state.x - enemy.x) < 256 * S and absi(state.y - enemy.y) < 256 * S
	if near:
		if enemy.mode in [0, 3]:
			enemy.mode = 1
			enemy.head_size = 0
		if enemy.mode == 1:
			enemy.head_size = mini(15, enemy.head_size + 1)
			if enemy.head_size == 15:
				enemy.mode = 2
		track(enemy, state)
	elif enemy.mode:
		enemy.mode = 3
		enemy.head_size = maxi(0, enemy.head_size - 1)
		if enemy.head_size == 0:
			enemy.mode = 0


static func track(enemy: Dictionary, state: Dictionary) -> void:
	enemy.facing = 1 if state.x > enemy.x else -1
	var dx: int = state.x - enemy.x
	# Ground heads track the upper half-turn, hanging heads the lower one.
	var dy: int = state.y - pivot_y(enemy)
	dy = maxi(0, dy) if hanging(enemy) else mini(0, dy)
	if dx == 0 and dy == 0:
		enemy.head_dx = S
		enemy.head_dy = 0
		return
	var length := Motion.root(dx * dx + dy * dy)
	enemy.head_dx = dx * S / length
	enemy.head_dy = dy * S / length


static func head_box(enemy: Dictionary) -> Array:
	var width: int = 16 * S + 48 * S * enemy.head_size / 15
	var height: int = 16 * S + 38 * S * enemy.head_size / 15
	var left := 1000000000
	var right := -1000000000
	var top := left
	var bottom := right
	for index in range(0, HEAD.size(), 2):
		var x: int = HEAD[index] * width / 64
		var y: int = HEAD[index + 1] * height / 54
		if enemy.facing > 0:
			y = -y  # Flip the head vertically when the stem faces right.
		var rotated_x: int = (x * enemy.head_dx - y * enemy.head_dy) / S
		var rotated_y: int = (x * enemy.head_dy + y * enemy.head_dx) / S
		left = mini(left, rotated_x)
		right = maxi(right, rotated_x)
		top = mini(top, rotated_y)
		bottom = maxi(bottom, rotated_y)
	var pivot_x: int = enemy.x + enemy.facing * 2 * S
	var pivot := pivot_y(enemy)
	return [pivot_x + left, pivot + top, pivot_x + right, pivot + bottom]


static func capture(enemy: Dictionary, index: int, state: Dictionary) -> void:
	if state.invulnerable or state.captured_by or enemy.mode not in [1, 2]:
		return
	var bounds := head_box(enemy)
	if (
		state.x + 12 * S > bounds[0]
		and state.x - 12 * S < bounds[2]
		and state.y > bounds[1]
		and state.y - 56 * S < bounds[3]
	):
		enemy.mode = 4
		enemy.pin_size = enemy.head_size
		enemy.timer = 210
		enemy.phase = 0
		state.captured_by = index + 1
		state.hits += 1
		state.vx = 0
		state.vy = 0
		state.flutter_remaining = 0
		state.jump_buffer = 0
		state.on_floor = 0
		pin_player(enemy, state)


static func pin_player(enemy: Dictionary, state: Dictionary) -> void:
	var width: int = 16 * S + 48 * S * enemy.pin_size / 15
	var reach := CHEW_REACH * width / 64
	state.x = enemy.x + enemy.facing * 2 * S + reach * enemy.head_dx / S
	state.y = pivot_y(enemy) + reach * enemy.head_dy / S


static func release(enemy: Dictionary, state: Dictionary) -> void:
	enemy.mode = 5
	enemy.timer = 30
	state.captured_by = 0
	state.invulnerable = 120
	Life.start_hurt(state, Life.KNOCKED_LOCK, true)
	state.hurt_deceleration = 648
	state.vx = enemy.facing * 400 * 60
	state.vy = -384 * 60
	state.on_floor = 0
