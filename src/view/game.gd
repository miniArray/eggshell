extends Node
## Composition/effects boundary: fixed-step simulation, input, view and storage.

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Store = preload("res://src/save/store.gd")
const Settings = preload("res://src/save/settings.gd")
const View = preload("res://src/view/level_view.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const FrameLogger = preload("res://src/diag/frame_log.gd")
var state: Dictionary
var world: Dictionary
var _view: Node2D
var _store := Store.new()
var _save_dir: String
var _resume := true
var _initialized := false
var _closing := false
var _replay: Array = []
var _start_usec := 0
var _screen_wait := 0
var _options := {}
var _shutdown_request := ""
var _profile_file: FileAccess
var _sim_usec := 0
var _slot_bytes := PackedByteArray()


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_shutdown_request = OS.get_environment("EGGSHELL_SHUTDOWN_REQUEST")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var pair := argument.trim_prefix("--").split("=", true, 1)
			_options[pair[0]] = pair[1] if pair.size() == 2 else "true"
	var pack: String = _options.get("pack", OS.get_environment("EGGSHELL_PACK"))
	if pack.is_empty():
		pack = Pack.DEFAULT_PATH
	if _options.has("placeholder") or Pack.read(pack).is_empty():
		pack = ""
	print("EGGSHELL_PACK ", pack if not pack.is_empty() else "placeholders")
	var code := _level_code()
	if code.is_empty():
		return
	var facts := CollisionTable.read()
	var result := World.build(code, facts)
	if not result.ok:
		fail(result.error)
		return
	world = result.world
	state = State.create(world)
	_save_dir = ProjectSettings.globalize_path(_options.get("save-dir", "user://"))
	var settings := Settings.read_or_create(_save_dir)
	_resume = settings.resume
	if not settings.error.is_empty():
		printerr(settings.error)
	if _store.start() != OK:
		fail("Cannot start save worker")
		return
	if _resume:
		load_slot("autosave")
	if _options.has("replay"):
		var replay: Variant = JSON.parse_string(FileAccess.get_file_as_string(_options.replay))
		if not replay is Array:
			fail("Replay must be an action-mask array")
			return
		for mask: Variant in replay:
			if not valid_replay_mask(mask):
				fail("Replay masks must be integers 0..%d" % InputBits.MASK)
				return
		_replay = replay
	setup_input()
	var joypads := Input.get_connected_joypads()
	if joypads.is_empty():
		print("EGGSHELL_JOYPADS none")
	else:
		for joypad: int in joypads:
			print("EGGSHELL_JOYPAD ", joypad, " ", Input.get_joy_name(joypad))
	_view = View.new()
	add_child(_view)
	_view.setup(world, pack)
	if not _setup_diagnostics():
		return
	_start_usec = Time.get_ticks_usec()
	_initialized = true
	print("EGGSHELL_START ", state.frame)


func _setup_diagnostics() -> bool:
	if _options.has("stall-probe"):
		var probe := preload("res://src/diag/stall_probe.gd").new()
		add_child(probe)
		if (
			probe.setup(self, _view, _options.get("frame-log", _save_dir.path_join("frames.csv")))
			!= OK
		):
			fail("Cannot open stall probe logs")
			return false
	if _options.has("profile"):
		var path: String = (
			_options.get("frame-log", _save_dir.path_join("frames.csv")) + ".profile.csv"
		)
		_profile_file = FileAccess.open(path, FileAccess.WRITE)
		if _profile_file == null:
			fail("Cannot open profile log")
			return false
		_profile_file.store_line(
			(
				"frame,sim_ms,view_ms,engine_process_ms,engine_physics_ms,"
				+ "draw_calls,render_objects,video_memory_bytes"
			)
		)
	return true


func _level_code() -> String:
	# Levels come from user input, never from a graphics pack.
	if _options.has("level-code"):
		var path: String = _options["level-code"]
		if not FileAccess.file_exists(path):
			fail("Level file not found: " + path)
			return ""
		var code := FileAccess.get_file_as_string(path)
		if code.is_empty():
			fail("Level file is empty or unreadable: " + path)
		return code
	fail("Pass --level-code=PATH to select a level")
	return ""


func _physics_process(_delta: float) -> void:
	if not _initialized or _closing:
		return
	if not _shutdown_request.is_empty() and FileAccess.file_exists(_shutdown_request):
		_closing = true
		get_tree().quit()
		return
	if _options.has("at-frame") and state.frame >= int(_options["at-frame"]):
		return
	var input := 0
	if _options.has("replay"):
		input = int(_replay[state.frame]) if state.frame < _replay.size() else 0
	else:
		input = action_mask()
	var began := Time.get_ticks_usec() if _profile_file != null else 0
	Sim.advance(state, input, world)
	if _profile_file != null:
		_sim_usec += Time.get_ticks_usec() - began
	if _options.has("trace"):
		print("EGGSHELL_TICK ", state.frame)
	if state.frame % 60 == 0 and not state.goal_reached and _resume:
		save_slot("autosave")
	if state.goal_reached:
		print("EGGSHELL_GOAL ", state.frame)
		set_physics_process(false)
		if _resume:
			save_slot("autosave")
	if _options.has("exit-frame") and state.frame >= int(_options["exit-frame"]):
		get_tree().quit()
	if _options.has("close-frame") and state.frame >= int(_options["close-frame"]):
		notification(NOTIFICATION_WM_CLOSE_REQUEST)


func _process(_delta: float) -> void:
	if not _initialized:
		return
	if not _shutdown_request.is_empty() and FileAccess.file_exists(_shutdown_request):
		_closing = true
		get_tree().quit()
	var began := Time.get_ticks_usec() if _profile_file != null else 0
	_view.render(state)
	if _profile_file != null:
		_profile_file.store_line(
			(
				"%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%d"
				% [
					state.frame,
					_sim_usec / 1000.0,
					(Time.get_ticks_usec() - began) / 1000.0,
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
				]
			)
		)
		_sim_usec = 0
	for result: Dictionary in _store.results():
		print("EGGSHELL_SAVE ", JSON.stringify(result))
		if result.error != OK:
			printerr("Save write failed: ", result.error)
	if (
		_options.has("stop-after")
		and Time.get_ticks_usec() - _start_usec >= float(_options["stop-after"]) * 1000000
	):
		get_tree().quit()
	if (
		_options.has("screenshot")
		and state.frame >= int(_options.get("at-frame", "0"))
		and (
			Time.get_ticks_usec() - _start_usec
			>= float(_options.get("capture-delay", "2")) * 1000000
		)
	):
		_screen_wait += 1
		if _screen_wait == 3:
			capture.call_deferred()


func capture() -> void:
	await RenderingServer.frame_post_draw
	var path: String = _options.screenshot
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("EGGSHELL_SCREENSHOT ", path, " error=", error, " frame=", state.frame)
	get_tree().quit(0 if error == OK else 1)


func _unhandled_input(_event: InputEvent) -> void:
	if not _initialized:
		return
	var modifier := Input.is_action_pressed("slot_modifier")
	if (
		Input.is_action_just_pressed("save")
		or (modifier and Input.is_action_just_pressed("slot_save"))
	):
		save_slot("slot")
	if (
		Input.is_action_just_pressed("load")
		or (modifier and Input.is_action_just_pressed("slot_load"))
	):
		load_slot("slot")
		set_physics_process(not bool(state.goal_reached))


func save_slot(slot: String) -> void:
	var bytes := Snapshot.encode(state)
	if bytes.is_empty():
		printerr("Save skipped: invalid snapshot state")
		return
	if slot == "slot":
		_slot_bytes = bytes
	_store.submit(_save_dir.path_join(slot + ".egg"), bytes, state.frame)


func load_slot(slot: String) -> void:
	var path := _save_dir.path_join(slot + ".egg")
	var bytes := _slot_bytes if slot == "slot" else PackedByteArray()
	if bytes.is_empty():
		if not FileAccess.file_exists(path):
			return
		bytes = FileAccess.get_file_as_bytes(path)
	var loaded := Snapshot.decode(bytes, world.identity, world)
	if loaded.ok:
		state = loaded.state
		print("EGGSHELL_RESUME ", slot, " ", state.frame)
	else:
		printerr("Ignoring ", slot, ": ", loaded.error)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func _exit_tree() -> void:
	_closing = true
	if _initialized and _resume:
		save_slot("autosave")
	_store.close()
	if _profile_file != null:
		_profile_file.close()
	if _initialized:
		for result: Dictionary in _store.results():
			print("EGGSHELL_SAVE ", JSON.stringify(result))
		print("EGGSHELL_EXIT ", state.frame)
		var logger := get_node_or_null("/root/FrameLog") as FrameLogger
		if logger != null:
			logger.finish()
		var ack := OS.get_environment("EGGSHELL_EXIT_ACK")
		if not ack.is_empty():
			var file := FileAccess.open(ack, FileAccess.WRITE)
			if file == null:
				printerr("Cannot acknowledge save drain")
			else:
				file.close()


func fail(message: String) -> void:
	printerr(message)
	get_tree().quit(1)


func setup_input() -> void:
	var keys := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"jump": [KEY_SPACE, KEY_Z],
		"use": [KEY_SHIFT, KEY_X],
		"move_up": [KEY_UP, KEY_W],
		"move_down": [KEY_DOWN, KEY_S],
		"throw": [KEY_C],
		"aim_lock": [KEY_V],
		"save": [KEY_F5],
		"load": [KEY_F9],
		"slot_modifier": [],
		"slot_save": [],
		"slot_load": []
	}
	for action: String in keys:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.25)
		for key: int in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	var buttons := {
		"move_left": [JOY_BUTTON_DPAD_LEFT],
		"move_right": [JOY_BUTTON_DPAD_RIGHT],
		"jump": [JOY_BUTTON_A, JOY_BUTTON_B],
		"use": [JOY_BUTTON_X, JOY_BUTTON_Y],
		"move_up": [JOY_BUTTON_DPAD_UP],
		"move_down": [JOY_BUTTON_DPAD_DOWN],
		"throw": [JOY_BUTTON_LEFT_SHOULDER],
		"aim_lock": [JOY_BUTTON_RIGHT_SHOULDER],
		"slot_modifier": [JOY_BUTTON_BACK],
		"slot_save": [JOY_BUTTON_LEFT_SHOULDER],
		"slot_load": [JOY_BUTTON_RIGHT_SHOULDER]
	}
	for action: String in buttons:
		for button: int in buttons[action]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
	for direction in [-1, 1]:
		var event := InputEventJoypadMotion.new()
		event.axis = JOY_AXIS_LEFT_X
		event.axis_value = direction
		InputMap.action_add_event("move_left" if direction < 0 else "move_right", event)
		var vertical := InputEventJoypadMotion.new()
		vertical.axis = JOY_AXIS_LEFT_Y
		vertical.axis_value = direction
		InputMap.action_add_event("move_up" if direction < 0 else "move_down", vertical)


static func action_mask() -> int:
	var mask := (
		int(Input.is_action_pressed("move_left")) * InputBits.LEFT
		| int(Input.is_action_pressed("move_right")) * InputBits.RIGHT
		| int(Input.is_action_pressed("jump")) * InputBits.JUMP
		| int(Input.is_action_pressed("use")) * InputBits.USE
		| int(Input.is_action_pressed("move_up")) * InputBits.UP
		| int(Input.is_action_pressed("move_down")) * InputBits.DOWN
	)
	# Slot chords keep their existing meaning and do not also throw or change aim.
	if not Input.is_action_pressed("slot_modifier"):
		mask |= int(Input.is_action_pressed("throw")) * InputBits.THROW
		mask |= int(Input.is_action_pressed("aim_lock")) * InputBits.LOCK
	return mask


static func valid_replay_mask(value: Variant) -> bool:
	return (
		(value is float or value is int)
		and value >= 0
		and value <= InputBits.MASK
		and floor(value) == value
	)
