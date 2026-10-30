extends SceneTree
## Deliberate lifetime boundary after a normal-input prefix, not target route activity.
const World = preload("res://src/sim/world.gd")
const Table = preload("res://src/level/collision_table.gd")
const State = preload("res://src/sim/play_state.gd")
const Step = preload("res://src/sim/step.gd")
const Life = preload("res://src/sim/life.gd")
const Snapshot = preload("res://src/save/snapshot.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var built := World.build(FileAccess.get_file_as_string(args[0]), Table.read())
	if not built.ok:
		quit(1)
		return
	var state := State.create(built.world)
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	for tick in 120:
		Step.advance(state, int(inputs[tick]), built.world)
	if state.move_action != 2 or not Life.quick_restart(state):
		quit(1)
		return
	FileAccess.open(args[2] + "/dead-before.v10", FileAccess.WRITE).store_buffer(
		Snapshot.encode(state)
	)
	Step.advance(state, 0, built.world)
	var height := -1
	for entity: Dictionary in state.entities:
		if entity.id == "post96":
			height = entity.height
	if height != 64 * 3600 or state.life_phase != 3:
		quit(1)
		return
	FileAccess.open(args[2] + "/dead-after.v10", FileAccess.WRITE).store_buffer(
		Snapshot.encode(state)
	)
	print("POST_DEAD_BODY_BOUNDARY_ORACLE_DONE prefix=120 quick_restart=true post_height=64")
	quit(0)
