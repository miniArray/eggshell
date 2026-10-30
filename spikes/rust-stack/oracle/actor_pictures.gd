extends SceneTree
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Actor = preload("res://src/sim/types/actor.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Pose = preload("res://src/view/player_pose.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var built := World.build(FileAccess.get_file_as_string(args[0]), Collision.read())
	if not built.ok:
		push_error(str(built))
		quit(1)
		return
	var world: Dictionary = built.world
	var stream := FileAccess.open(args[1], FileAccess.READ)
	var pictures := []
	while stream.get_position() < stream.get_length():
		var bytes := stream.get_buffer(stream.get_32())
		var decoded := Snapshot.decode(bytes, world.identity, world)
		if not decoded.ok:
			push_error(str(decoded))
			quit(1)
			return
		var state: Dictionary = decoded.state
		var entities := []
		for entity: Dictionary in state.entities:
			if entity.code not in ["e1", "e2", "e3", "e5"]:
				continue
			entities.append(
				{
					"token": entity.token,
					"body": Motion.box(entity, entity.code),
					"view": Actor.view_state(entity, state),
					"head": Actor.head_box(entity)
				}
			)
		pictures.append({"player": Pose.select(state), "entities": entities})
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(pictures, "", false, true))
	print("ACTOR_PICTURES_ORACLE_DONE snapshots=%d" % pictures.size())
	quit(0)
