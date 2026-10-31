extends SceneTree
## Diagnosis only: replay a fixture route and print the companion bubble's collision view
## (position, speed, wall test and nearby solid rows) for a tick window. No state edits.
const World = preload("res://src/sim/world.gd")
const Table = preload("res://src/level/collision_table.gd")
const State = preload("res://src/sim/play_state.gd")
const Step = preload("res://src/sim/step.gd")
const Collision = preload("res://src/sim/collision.gd")
const Life = preload("res://src/sim/life.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var code := FileAccess.get_file_as_string(args[0])
	var decoded: Variant = JSON.parse_string(code)
	if decoded is String:
		code = decoded
	var built := World.build(code, Table.read())
	if not built.ok:
		quit(1)
		return
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var first := int(args[2])
	var last := int(args[3])
	var state := State.create(built.world)
	for tick in last:
		Step.advance(state, int(inputs[tick]), built.world)
		if tick + 1 < first:
			continue
		var here := {"x": state.recovery_x, "y": state.recovery_y}
		var body: Array = Life._bubble_body()
		var context: Dictionary = built.world.get("solids_step", {})
		var rows := []
		for row: Dictionary in context.get("rows", []):
			rows.append(
				(
					"%s@%d,%d st=%d"
					% [row.entity.code, row.entity.x / 3600, row.entity.y / 3600, row.status]
				)
			)
		print(
			(
				"BUBBLE tick=%d rx=%d ry=%d cvx=%d dir=%d wall_r=%s overlaps=%s rows=%s"
				% [
					tick + 1,
					state.recovery_x,
					state.recovery_y,
					state.companion_vx,
					state.companion_direction,
					Collision.by_wall(here, built.world, body, 1),
					Collision.overlaps(here, built.world, body),
					",".join(rows)
				]
			)
		)
	quit(0)
