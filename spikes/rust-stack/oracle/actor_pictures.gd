extends SceneTree
const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Actor = preload("res://src/sim/types/actor.gd")
const Motion = preload("res://src/sim/enemy_motion.gd")
const Pose = preload("res://src/view/player_pose.gd")
const Stilt = preload("res://src/sim/types/stilt_walker.gd")
const Dressing = preload("res://src/view/pack_dressing.gd")
const View = preload("res://src/view/level_view.gd")
const Post = preload("res://src/sim/types/pound_post.gd")


func enemy_visible(entity: Dictionary, state: Dictionary) -> bool:
	var style: Dictionary = (
		Stilt.view_state(entity, state) if entity.code == "e35" else Actor.view_state(entity, state)
	)
	return (
		View.inactive_shown(entity)
		or (
			entity.status == 1
			and not entity.held
			and not entity.hidden
			and style.get("visible", true)
		)
	)


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
			if entity.code == "o23":
				entities.append(
					{
						"token": entity.token,
						"body": Post.bounds(entity),
						"view": Post.view_state(entity, state),
						"head": [],
						"visible": Post.view_state(entity, state).visible
					}
				)
				continue
			if entity.code == "o6":
				entities.append(
					{
						"token": entity.token,
						"body": [0, 0, 0, 0],
						"view": {},
						"head": [],
						"visible": Dressing._entity_visible(entity)
					}
				)
				continue
			if entity.code not in ["e1", "e2", "e3", "e5", "e35"]:
				continue
			entities.append(
				{
					"token": entity.token,
					"visible": enemy_visible(entity, state),
					"inactive": View.inactive_shown(entity),
					"body":
					(
						Stilt.bounds(entity)
						if entity.code == "e35"
						else Motion.box(entity, entity.code)
					),
					"view":
					(
						Stilt.view_state(entity, state)
						if entity.code == "e35"
						else Actor.view_state(entity, state)
					),
					"head": [] if entity.code == "e35" else Actor.head_box(entity)
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
