extends SceneTree
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var cases := [
		[null, null],
		[-1, -5],
		[3, 7],
		[3.0, 7.0],
		[2147483647, 0],
		[-2147483648, 0],
		[0.5, 0],
		["3", 0],
		[2147483648, 0],
		[-2147483649, 0],
		[true, 0]
	]
	var result := []
	for values: Array in cases:
		var level := source.duplicate(true)
		for index in 2:
			var field: String = ["flowers", "redcoins"][index]
			if values[index] == null:
				level.erase(field)
			else:
				level[field] = values[index]
		var built := World.build(JSON.stringify(level), Collision.read())
		var record := {"input": values, "ok": built.ok}
		if built.ok:
			record.flowers_target = built.world.flowers_target
			record.redcoins_target = built.world.redcoins_target
		result.append(record)
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(result, "", false, true))
	print("WORLD_COUNTS_ORACLE_DONE cases=%d" % result.size())
	quit(0)
