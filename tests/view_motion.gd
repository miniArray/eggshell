extends SceneTree
## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.
const Motion = preload("res://src/view/view_motion.gd")
const FrameLoop = preload("res://src/view/frame_loop.gd")
const Settings = preload("res://src/save/settings.gd")
const View = preload("res://src/view/level_view.gd")
const Life = preload("res://src/sim/life.gd")
const Registry = preload("res://src/sim/registry.gd")
const S := 3600
var _checks := 0
var _failures := 0


func _initialize() -> void:
	blend_checks()
	snap_checks()
	loop_checks()
	settings_checks()
	inactive_checks()
	print("VIEW_MOTION_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


static func sample() -> Dictionary:
	var walker := {"token": 1, "code": "e1", "x": 100 * S, "y": 50 * S, "status": 1}
	var pad := {"token": 2, "code": "o11", "x": 10 * S, "y": 10 * S, "squash": 0}
	var coin := {"token": 3, "code": "o1", "x": 40 * S, "y": 40 * S}
	return {
		"frame": 10,
		"map_index": 1,
		"life_phase": Life.PLAY,
		"x": 200 * S,
		"y": 300 * S,
		"camera_x": 200 * S,
		"camera_y": 272 * S,
		"recovery_x": 0,
		"recovery_y": 0,
		"entities": [walker, pad, coin],
		"enemies": [walker],
		"springs": [pad],
	}


## Advance a sample by one frame, moving the player and the walker.
static func moved(state: Dictionary, player_dx: int, walker_dx: int) -> void:
	state.frame += 1
	state.x += player_dx
	state.camera_x += player_dx
	state.entities[0].x += walker_dx


func blend_checks() -> void:
	var state := sample()
	var pose := Motion.capture(state)
	var before := var_to_bytes(state)
	moved(state, 8 * S, -4 * S)
	var after := var_to_bytes(state)
	var half := Motion.blend(pose, state, 0.5)
	check(var_to_bytes(state) == after, "Blending never writes the state")
	check(not is_same(half, state), "A blend is a separate picture")
	check(half.x == 204 * S and half.camera_x == 204 * S, "Player and camera move halfway")
	check(half.y == 300 * S, "An unchanged axis stays put")
	check(half.entities[0].x == 98 * S, "A moving row moves halfway")
	check(not is_same(half.entities[0], state.entities[0]), "A moving row is copied")
	check(is_same(half.entities[2], state.entities[2]), "A still row is shared")
	check(is_same(half.enemies[0], half.entities[0]), "The enemy read view shows the blended row")
	check(is_same(half.springs[0], state.springs[0]), "The pad read view keeps still rows")
	check(half.frame == state.frame, "The picture keeps the current frame")
	check(is_same(Motion.blend(pose, state, 1.0), state), "Fraction one draws the state")
	var start := Motion.blend(pose, state, 0.0)
	check(start.x == 200 * S and start.entities[0].x == 100 * S, "Fraction zero draws the pose")
	check(var_to_bytes(state) == after and before != after, "State bytes unchanged")
	# Rows matched by token, even after reordering or a new runtime row.
	var reordered := sample()
	var reordered_pose := Motion.capture(reordered)
	reordered.frame += 1
	var walker: Dictionary = reordered.entities.pop_front()
	walker.x += 2 * S
	reordered.entities.append(walker)
	reordered.entities.append({"token": 1000001, "code": "o7", "x": 0, "y": 0})
	var matched := Motion.blend(reordered_pose, reordered, 0.5)
	check(matched.entities[2].x == 101 * S, "Rows are matched by token")
	check(is_same(matched.entities[3], reordered.entities[3]), "A new row draws where it is")


func snap_checks() -> void:
	var cases := {
		"a replaced state":
		## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
		## No level, rendering or audio output is used.
		## Advance a sample by one frame, moving the player and the walker.
		# Rows matched by token, even after reordering or a new runtime row.
		func(state: Dictionary) -> Dictionary:
## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

			var copy := state.duplicate(true)
			moved(copy, S, 0)
			return copy,
		"a frame gap":
		## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
		## No level, rendering or audio output is used.
		## Advance a sample by one frame, moving the player and the walker.
		# Rows matched by token, even after reordering or a new runtime row.
		func(state: Dictionary) -> Dictionary:
## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

			moved(state, S, 0)
			state.frame += 1
			return state,
		"a map change":
		## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
		## No level, rendering or audio output is used.
		## Advance a sample by one frame, moving the player and the walker.
		# Rows matched by token, even after reordering or a new runtime row.
		func(state: Dictionary) -> Dictionary:
## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

			moved(state, S, 0)
			state.map_index = 2
			return state,
		"a respawn":
		## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
		## No level, rendering or audio output is used.
		## Advance a sample by one frame, moving the player and the walker.
		# Rows matched by token, even after reordering or a new runtime row.
		func(state: Dictionary) -> Dictionary:
## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

## Picture blending, zoom settings and the inactive-enemy rule on synthetic states.
## No level, rendering or audio output is used.

## Advance a sample by one frame, moving the player and the walker.

			# Rows matched by token, even after reordering or a new runtime row.

			moved(state, S, 0)
			state.life_phase = Life.FADE_IN
			return state,
	}
	for name: String in cases:
		var state := sample()
		if name == "a respawn":
			state.life_phase = Life.FADE_OUT
		var pose := Motion.capture(state)
		var next: Dictionary = cases[name].call(state)
		check(is_same(Motion.blend(pose, next, 0.5), next), "No blend across " + name)
	var state := sample()
	var pose := Motion.capture(state)
	moved(state, 65 * S, 64 * S)
	var picture := Motion.blend(pose, state, 0.5)
	check(picture.x == state.x and picture.camera_x == state.camera_x, "A teleport snaps")
	check(picture.entities[0].x == 132 * S, "A move of exactly the limit still blends")
	check(Motion.snaps({}, state), "An empty pose snaps")


func loop_checks() -> void:
	check(FrameLoop.wants_smooth("auto", 120.0), "Auto smooths above 60 Hz")
	check(not FrameLoop.wants_smooth("auto", 60.0), "Auto keeps 60 Hz unblended")
	check(not FrameLoop.wants_smooth("auto", -1.0), "Auto without a known rate is off")
	check(FrameLoop.wants_smooth("on", 60.0) and not FrameLoop.wants_smooth("off", 240.0), "Force")
	var loop := FrameLoop.new()
	loop.smooth = true
	var state := sample()
	loop.tick()
	var motion := Motion.new()
	motion.before_step(state, 1)
	moved(state, 8 * S, 0)
	check(motion.shown(state, 1, 0.5).x == 204 * S, "A fresh pose blends")
	check(is_same(motion.shown(state, 2, 0.5), state), "A tick without a step draws the state")
	motion.clear()
	check(is_same(motion.shown(state, 1, 0.5), state), "A cleared pose draws the state")
	check(is_same(loop.picture(state, 0.5), state), "No step yet draws the state")
	check(is_same(loop.picture(state, 0.5, false), state), "Paused steps draw the state")
	loop.smooth = false
	check(is_same(loop.picture(state, 0.5), state), "Without smoothing the state is drawn")


func settings_checks() -> void:
	var directory := "/tmp/eggshell-view-settings-%d" % OS.get_process_id()
	var path := directory.path_join("settings.json")
	var created := Settings.read_or_create(directory)
	check(created.zoom == 0 and created.error.is_empty(), "New settings start unzoomed")
	check(Settings.save_zoom(directory, 3).is_empty(), "Zoom saves")
	var saved := Settings.read_or_create(directory)
	check(saved.zoom == 3 and saved.music_volume == 80 and saved.resume, "Zoom keeps other keys")
	Settings.save_zoom(directory, 99)
	check(Settings.read_or_create(directory).zoom == Settings.ZOOM_LIMIT, "Saved zoom is limited")
	check(not FileAccess.file_exists(path + ".tmp"), "No temporary file remains")
	for bad: Variant in [1.5, "2", true, null, 17, -17]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(
			JSON.stringify({"version": 1, "resume_where_i_left_off": true, "zoom": bad})
		)
		file.close()
		var result := Settings.read_or_create(directory)
		check(result.zoom == 0 and not result.error.is_empty(), "Invalid zoom %s uses 0" % [bad])
	for good: int in [-16, -1, 16]:
		Settings.save_zoom(directory, good)
		check(Settings.read_or_create(directory).zoom == good, "Zoom %d round-trips" % good)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func inactive_checks() -> void:
	var row := {"source_index": 0, "status": Registry.WAITING, "can_respawn": 1}
	check(View.inactive_shown(row), "A waiting placed enemy is drawn inactive")
	row.status = Registry.QUEUED
	check(View.inactive_shown(row), "A queued enemy that can return is drawn inactive")
	row.can_respawn = 0
	check(not View.inactive_shown(row), "A queued enemy that cannot return is hidden")
	row.status = Registry.ACTIVE
	check(not View.inactive_shown(row), "An active enemy draws normally")
	row.status = Registry.DEFEATED
	check(not View.inactive_shown(row), "A defeated enemy stays hidden")
	check(
		not View.inactive_shown({"source_index": -1, "status": Registry.WAITING}),
		"Runtime rows are never drawn inactive"
	)
	check(
		not View.inactive_shown({"source_index": 0, "status": Registry.WAITING, "held": 1}),
		"Held rows are not drawn"
	)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
