extends SceneTree
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Simulation = preload("res://src/sim/step.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		quit(1)
		return
	var code := FileAccess.get_file_as_string(args[0])
	var built := World.build(code, Collision.read())
	if not built.ok:
		push_error(str(built))
		quit(1)
		return
	var world: Dictionary = built.world
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var stream := FileAccess.open(args[2], FileAccess.READ)
	var source := FileAccess.get_file_as_bytes(args[3])
	var start := int(args[4])
	for tick in start + 1:
		var size := stream.get_32()
		var expected := stream.get_buffer(size)
		if tick == start and source != expected:
			push_error("Rust snapshot differs from original at restore point")
			quit(1)
			return
	var decoded := Snapshot.decode(source, world.identity, world)
	if not decoded.ok:
		push_error("Godot rejected Rust-produced snapshot: " + str(decoded))
		quit(1)
		return
	var state: Dictionary = decoded.state
	for tick in range(start, inputs.size()):
		Simulation.advance(state, int(inputs[tick]), world)
		var size := stream.get_32()
		var expected := stream.get_buffer(size)
		var actual := Snapshot.encode(state)
		if actual != expected:
			push_error("Godot continuation mismatch after Rust restore at tick %d" % (tick + 1))
			quit(1)
			return
	print(
		(
			"B_TO_A_CONTINUATION_DONE restore_tick=%d continued_ticks=%d final_frame=%d"
			% [start, inputs.size() - start, state.frame]
		)
	)
	quit(0)
