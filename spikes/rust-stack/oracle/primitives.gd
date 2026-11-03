extends SceneTree
const Motion = preload("res://src/sim/enemy_motion.gd")
const Polygon = preload("res://src/sim/polygon.gd")
const Screen = preload("res://src/sim/screen.gd")
const World = preload("res://src/sim/world.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var result := {"rng": [], "sine": [], "round": [], "floor_div": [], "screen": [], "polygon": []}
	var state := {"rng": 1}
	for tick in 512:
		var a := Motion.random_ticks(state, -192 * 60, 192 * 60)
		var b := Motion.random_cycles(state)
		var c := Motion.random_ticks(state, 60, 150)
		result.rng.append([a, b, c, state.rng])
	for phase in range(-1000, 1001):
		result.sine.append([phase, 180, 16 * 3600, Motion.sine(phase, 180, 16 * 3600)])
	for value: float in [-1.5, -1.0, -0.5, -0.5 / 3600, 0.0, 0.5 / 3600, 0.5, 1.5, 0.1]:
		result.round.append([value, roundi(value * 3600)])
	for value in range(-10000, 10001, 13):
		result.floor_div.append([value, 3600, World.floor_div(value, 3600)])
	for size: Array in [[100, 100], [832, 448], [15040, 448], [1200, 600]]:
		for x in range(-100, 1300, 83):
			for y in range(-100, 700, 93):
				var follow := {"camera_x": x * 3600, "camera_y": y * 3600}
				var world := {"width": size[0] * 3600, "height": size[1] * 3600}
				result.screen.append(
					[
						follow.camera_x,
						follow.camera_y,
						world.width,
						world.height,
						Screen.centre_x(follow, world),
						Screen.centre_y(follow, world)
					]
				)
	var points := PackedInt64Array(
		[0, 0, 4 * 3600, 0, 4 * 3600, 2 * 3600, 2 * 3600, 2 * 3600, 2 * 3600, 4 * 3600, 0, 4 * 3600]
	)
	for x in range(-5, 16):
		for y in range(-5, 16):
			var box := [x * 900, y * 900, x * 900 + 900, y * 900 + 900]
			result.polygon.append(
				[Array(points), box, Polygon.overlaps_box(points, box[0], box[1], box[2], box[3])]
			)
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(result, "", false, true))
	print("PRIMITIVE_ORACLE_DONE rng=512 sine=2001 polygon=441")
	quit(0)
