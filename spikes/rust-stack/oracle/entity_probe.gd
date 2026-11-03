extends SceneTree
## Diagnosis only: replay a fixture route in Godot and print chosen entity fields every
## STRIDE ticks in a window. Usage: -- LEVEL INPUT FIRST LAST STRIDE FIELD,FIELD...
## A field written @name is read from the player state instead.
const World = preload("res://src/sim/world.gd")
const Table = preload("res://src/level/collision_table.gd")
const State = preload("res://src/sim/play_state.gd")
const Step = preload("res://src/sim/step.gd")


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
	var stride := int(args[4])
	var fields: PackedStringArray = args[5].split(",")
	var state := State.create(built.world)
	for tick in last:
		Step.advance(state, int(inputs[tick]), built.world)
		if tick + 1 < first or (tick + 1 - first) % stride:
			continue
		var rows := []
		var own := []
		for field in fields:
			if field.begins_with("@") and state.has(field.substr(1)):
				own.append("%s=%s" % [field.substr(1), state[field.substr(1)]])
		if not own.is_empty():
			rows.append("player " + " ".join(own))
		for entity: Dictionary in state.entities:
			if entity.code in ["o5"]:
				continue
			var parts := [
				"%s:%s@%d,%d" % [entity.id, entity.code, entity.x / 3600, entity.y / 3600]
			]
			for field in fields:
				if entity.has(field):
					parts.append("%s=%s" % [field, entity[field]])
			rows.append(" ".join(parts))
		print(
			(
				"ENTITIES tick=%d player=%d,%d pvy=%d floor=%d px=%d py=%d | %s"
				% [
					tick + 1,
					state.x / 3600,
					state.y / 3600,
					state.vy,
					state.on_floor,
					state.x,
					state.y,
					" ; ".join(rows)
				]
			)
		)
	quit(0)
