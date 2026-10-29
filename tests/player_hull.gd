extends SceneTree
## The contact hull holds every player box, and its miss test counts touching edges.
## Pure state only; no scenes, assets or recordings.
const State = preload("res://src/sim/play_state.gd")
const World = preload("res://src/sim/world.gd")
const Moves = preload("res://src/sim/moves.gd")
const Hull = preload("res://src/sim/player_hull.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	hull_checks()
	print("PLAYER_HULL_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## Every player box of every posture and action lies inside the contact hull.
func hull_checks() -> void:
	var state := {"x": 0, "y": 0, "vx": 0}
	var outside := []
	for action in range(Moves.NORMAL, Moves.SWALLOW + 1):
		for tick_count in [0, 1, 2, 3, 4, 5, 6, 8, 12, 20, 40, 60]:
			for flags in 64:
				state.move_action = action
				state.move_action_tick = tick_count
				state.move_posture_tick = tick_count
				state.move_duck = flags & 1
				state.move_held_id = flags & 2
				state.move_tongue_axis = (flags >> 2) & 1
				state.move_action_wet = (flags >> 3) & 1
				state.swimming = (flags >> 4) & 1
				state.move_dive = (flags >> 5) & 1
				state.move_water_transition = tick_count % 10
				state.vx = (flags & 1) * 100 * 60
				var box := Moves.player_box(state)
				if (
					box[0] < Hull.HULL[0]
					or box[1] < Hull.HULL[1]
					or box[2] > Hull.HULL[2]
					or box[3] > Hull.HULL[3]
				):
					outside.append([action, tick_count, flags, box])
	check(
		outside.is_empty(),
		"Every player box lies inside the contact hull: %s" % [outside.slice(0, 3)]
	)
	state.x = 100 * S
	state.y = 100 * S
	check(
		not Hull.misses(state, 112 * S, 40 * S, 200 * S, 40 * S),
		"The hull touches an area at its corner"
	)
	check(Hull.misses(state, 113 * S, 0, 200 * S, 200 * S), "The hull misses an area past its edge")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)
