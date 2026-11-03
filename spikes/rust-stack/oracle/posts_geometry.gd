extends SceneTree
## Fresh normal-input replay; queries must not alter any saved field.
const World = preload("res://src/sim/world.gd")
const Table = preload("res://src/level/collision_table.gd")
const State = preload("res://src/sim/play_state.gd")
const Step = preload("res://src/sim/step.gd")
const Collision = preload("res://src/sim/collision.gd")
const Post = preload("res://src/sim/types/pound_post.gd")
const Moves = preload("res://src/sim/moves.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const S := 3600


func sample(state: Dictionary, world: Dictionary) -> Dictionary:
	var rows := []
	var indexed := Collision.solid_rows(world)
	for entity: Dictionary in state.entities:
		if entity.code != "o23":
			continue
		var row: Dictionary = indexed[entity.token]
		var boxes: Array = row.old_boxes
		var live := Post.solid_box(entity)
		rows.append(
			{
				"token": entity.token,
				"old_position": [row.x, row.y],
				"live_position": [entity.x, entity.y],
				"old_box": null if boxes.is_empty() else boxes[0],
				"live_box": null if live.is_empty() else live
			}
		)
	var floor := Collision.floor_at(state, world, Moves.player_box(state))
	if floor <= -2:
		floor = Collision._selected(world, floor).row.entity.token
	var polygon_box_probes := []
	var polygon := PackedInt64Array(
		[
			-22 * S,
			-52 * S,
			0,
			-60 * S,
			22 * S,
			-52 * S,
			30 * S,
			-30 * S,
			22 * S,
			-8 * S,
			0,
			0,
			-22 * S,
			-8 * S,
			-30 * S,
			-30 * S
		]
	)
	for entity: Dictionary in state.entities:
		if entity.code == "o23":
			var body := {"x": entity.x - 46 * S, "y": entity.y - entity.height + 15 * S}
			polygon_box_probes.append(
				Collision.overlaps(body, world, [-30 * S, -60 * S, 30 * S, 0, polygon])
			)
	return {
		"saved_frame": state.frame,
		"rows": rows,
		"floor_token": floor,
		"polygon_box_probes": polygon_box_probes
	}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var built := World.build(FileAccess.get_file_as_string(args[0]), Table.read())
	if not built.ok:
		quit(1)
		return
	var world: Dictionary = built.world
	var state := State.create(world)
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var frames := []
	for tick in range(inputs.size() + 1):
		var before := Snapshot.encode(state)
		frames.append(sample(state, world))
		if before != Snapshot.encode(state):
			push_error("Geometry query changed saved state")
			quit(1)
			return
		if tick < inputs.size():
			Step.advance(state, int(inputs[tick]), world)
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(frames, "", false, true))
	print("POST_GEOMETRY_ORACLE_DONE snapshots=%d state_edits=0" % frames.size())
	quit(0)
