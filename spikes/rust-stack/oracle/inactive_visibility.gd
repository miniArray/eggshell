extends SceneTree
## Deliberate policy boundary cases, not legal gameplay coverage.
const View = preload("res://src/view/level_view.gd")
const Actor = preload("res://src/sim/types/actor.gd")
const Stilt = preload("res://src/sim/types/stilt_walker.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var cases := []
	for code: String in ["e1", "e2", "e3", "e5", "e35"]:
		for source_index: int in [0, -1]:
			for status in 4:
				for respawn in 2:
					for held in 2:
						for hidden in 2:
							var entity := {
								"code": code,
								"source_index": source_index,
								"status": status,
								"can_respawn": respawn,
								"held": held,
								"hidden": hidden,
								"mode": 0,
								"variant": 0,
								"ground_form": 0,
								"roll": 0,
								"height": 244800
							}
							var inactive := View.inactive_shown(entity)
							var style: Dictionary = (
								Stilt.view_state(entity, {})
								if code == "e35"
								else Actor.view_state(entity, {})
							)
							var active: bool = (
								status == 1
								and held == 0
								and hidden == 0
								and style.get("visible", true)
							)
							cases.append(
								{
									"code": code,
									"source_index": source_index,
									"status": status,
									"can_respawn": respawn,
									"held": held,
									"hidden": hidden,
									"inactive": inactive,
									"visible": inactive or active
								}
							)
	var output := FileAccess.open(args[0], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(cases, "", false, true))
	print("INACTIVE_VISIBILITY_ORACLE_DONE cases=%d boundary_only=true" % cases.size())
	quit(0)
