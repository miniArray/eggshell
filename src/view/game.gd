extends Node
## Composition/effects boundary: fixed-step simulation, input, view and storage.
## The pause menu stops simulation steps while it is open; it never writes play state.

const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const InputBits = preload("res://src/sim/move_input.gd")
const Maps = preload("res://src/sim/maps.gd")
const Life = preload("res://src/sim/life.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Store = preload("res://src/save/store.gd")
const Settings = preload("res://src/save/settings.gd")
const View = preload("res://src/view/level_view.gd")
const Hud = preload("res://src/view/hud.gd")
const AudioPlayer = preload("res://src/view/audio_player.gd")
const FrameLoop = preload("res://src/view/frame_loop.gd")
const Menu = preload("res://src/view/menu_model.gd")
const MenuView = preload("res://src/view/menu_view.gd")
const MenuInput = preload("res://src/view/menu_input.gd")
const LevelList = preload("res://src/view/level_list.gd")
const PlayTimer = preload("res://src/view/play_timer.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
const Pack = preload("res://src/level/asset_pack.gd")
const FrameLogger = preload("res://src/diag/frame_log.gd")
## Options to use instead of the command line, for tests. Set before `_ready`.
var launch_options := {}
var state: Dictionary
var world: Dictionary
## The open menu, or a closed one. Steps run only while it is closed.
var menu := Menu.new()
var _view: Node2D
var _audio: Node
var _store := Store.new()
var _save_dir: String
## Slot and autosave files of the open level. With a level folder, each level has its own.
var _slot_dir: String
var _settings := {}
var _resume := true
var _initialized := false
var _playing := false
var _closing := false
var _replay: Array = []
var _start_usec := 0
var _screen_wait := 0
var _options := {}
var _pack := ""
var _facts := {}
var _shutdown_request := ""
var _profile_file: FileAccess
var _probe: Node
var _sim_usec := 0
var _slot_bytes := PackedByteArray()
var _loop := FrameLoop.new()
var _levels: Array = []
var _level_folder := ""
var _level_index := -1
var _menu_view: MenuView
var _menu_held := {}
var _timer: Node2D
## Input bits held when the menu closed. They reach the simulation after release,
## so the confirm press does not also jump.
var _suppressed := 0
var _goal_menu_shown := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_shutdown_request = OS.get_environment("EGGSHELL_SHUTDOWN_REQUEST")
	if launch_options.is_empty():
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--"):
				var pair := argument.trim_prefix("--").split("=", true, 1)
				_options[pair[0]] = pair[1] if pair.size() == 2 else "true"
	else:
		_options = launch_options.duplicate()
	_pack = _options.get("pack", OS.get_environment("EGGSHELL_PACK"))
	if _pack.is_empty():
		_pack = Pack.DEFAULT_PATH
	if _options.has("placeholder") or Pack.read(_pack).is_empty():
		_pack = ""
	print("EGGSHELL_PACK ", _pack if not _pack.is_empty() else "placeholders")
	if _options.has("levels"):
		_level_folder = ProjectSettings.globalize_path(_options.levels)
		var listed := LevelList.scan(_level_folder)
		if not listed.ok:
			fail(listed.error)
			return
		_levels = listed.levels
		print("EGGSHELL_LEVELS ", _levels.size())
	var code := ""
	if _options.has("level-code"):
		var read := _read_level(_options["level-code"])
		if not read.error.is_empty():
			fail(read.error)
			return
		code = read.code
	elif _levels.is_empty():
		fail("Pass --level-code=PATH or --levels=DIR to select a level")
		return
	_facts = CollisionTable.read()
	var built := {}
	if not code.is_empty():
		built = World.build(code, _facts)
		if not built.ok:
			fail(built.error)
			return
	_save_dir = ProjectSettings.globalize_path(_options.get("save-dir", "user://"))
	_settings = Settings.read_or_create(_save_dir)
	_resume = _settings.resume
	if not _settings.error.is_empty():
		printerr(_settings.error)
	if _store.start() != OK:
		fail("Cannot start save worker")
		return
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
	_loop.smooth = FrameLoop.wants_smooth(
		_options.get("smooth", "auto"), DisplayServer.screen_get_refresh_rate()
	)
	print("EGGSHELL_SMOOTH ", "on" if _loop.smooth else "off")
	_menu_view = MenuView.new()
	_menu_view.row_clicked.connect(_on_row_clicked)
	add_child(_menu_view)
	_timer = PlayTimer.new()
	_timer.visible = bool(_settings.play_timer)
	add_child(_timer)
	if not _setup_profile():
		return
	_start_usec = Time.get_ticks_usec()
	_initialized = true
	if built.is_empty():
		open_menu()
		return
	_start_level(built.world, _options["level-code"])
	if not _setup_probe():
		return
	print("EGGSHELL_START ", state.frame)


func _setup_profile() -> bool:
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


func _setup_probe() -> bool:
	if _options.has("stall-probe") and _probe == null:
		_probe = preload("res://src/diag/stall_probe.gd").new()
		add_child(_probe)
		if (
			_probe.setup(self, _view, _options.get("frame-log", _save_dir.path_join("frames.csv")))
			!= OK
		):
			fail("Cannot open stall probe logs")
			return false
	return true


## Read a level-code file. Levels come from user input, never from a graphics pack.
## Returns {"code": String, "error": String}.
static func _read_level(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"code": "", "error": "Level file not found: " + path}
	var code := FileAccess.get_file_as_string(path)
	if code.is_empty():
		return {"code": "", "error": "Level file is empty or unreadable: " + path}
	return {"code": code, "error": ""}


## Make `built` the open level: fresh state, its own autosave, a new view and audio.
func _start_level(built: Dictionary, path: String) -> void:
	if _playing and _resume:
		save_slot("autosave")
	_close_level()
	world = built
	state = State.create(world)
	_level_index = LevelList.find(_levels, path) if not _levels.is_empty() else -1
	_slot_dir = (
		_save_dir
		if _levels.is_empty()
		else _save_dir.path_join("levels").path_join(String(world.identity))
	)
	_slot_bytes = PackedByteArray()
	_goal_menu_shown = false
	if _resume:
		load_slot("autosave")
	_view = View.new()
	add_child(_view)
	_view.setup(world, _pack)
	_view.zoom = int(_settings.zoom)
	_audio = AudioPlayer.create(_view.audio, world, _settings, _options.has("mute"))
	add_child(_audio)
	_loop.restored()
	_playing = true
	set_physics_process(true)
	if not _levels.is_empty():
		print("EGGSHELL_LEVEL ", path)


func _close_level() -> void:
	_playing = false
	if _probe != null:
		# The probe watches one level's nodes; it ends when another level opens.
		print("EGGSHELL_PROBE stopped: level changed")
		_probe.queue_free()
		_probe = null
	for node: Node in [_view, _audio]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_view = null
	_audio = null


func _physics_process(_delta: float) -> void:
	if not _initialized or _closing:
		return
	_loop.tick()
	if not _shutdown_request.is_empty() and FileAccess.file_exists(_shutdown_request):
		_closing = true
		get_tree().quit()
		return
	if not _playing or menu.is_open():
		return
	if _options.has("at-frame") and state.frame >= int(_options["at-frame"]):
		return
	var input := 0
	if _options.has("replay"):
		input = int(_replay[state.frame]) if state.frame < _replay.size() else 0
	else:
		input = action_mask()
		_suppressed &= input
		input &= ~_suppressed
		# The quick death preference is a saved player field; it changes only between steps.
		var quick := int(bool(_settings.get("quick_death", false)))
		if int(state.get("quick_death", 0)) != quick:
			state.quick_death = quick
	var began := Time.get_ticks_usec() if _profile_file != null else 0
	# Sound follows each saved step inside the loop; it reads state and never writes it.
	_loop.step(state, input, world, _audio)
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
		# Automated runs (replays and screenshots) keep the plain completed picture.
		if not _goal_menu_shown and not _options.has("replay") and not _options.has("screenshot"):
			_goal_menu_shown = true
			open_menu()
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
	if _playing:
		_zoom_input()
		# Pictures blend saved states between fixed steps; the view never writes state.
		_view.render(
			_loop.picture(
				state,
				Engine.get_physics_interpolation_fraction(),
				is_physics_processing() and not menu.is_open()
			)
		)
		_timer.render(state, _view.get_viewport_rect().size)
	if _profile_file != null and _playing:
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
		and _playing
		and state.frame >= int(_options.get("at-frame", "0"))
		and (
			Time.get_ticks_usec() - _start_usec
			>= float(_options.get("capture-delay", "2")) * 1000000
		)
	):
		_screen_wait += 1
		if _screen_wait == 3:
			capture.call_deferred()


func _zoom_input() -> void:
	var step := (
		int(Input.is_action_just_pressed("zoom_in")) - int(Input.is_action_just_pressed("zoom_out"))
	)
	var reset := Input.is_action_just_pressed("zoom_reset")
	if step == 0 and not reset:
		return
	var plan: Dictionary = _view.plan
	_set_zoom(0 if reset else int(plan.get("zoom", _view.zoom)) + step)


## Set the zoom step within the current container's limits and save it.
func _set_zoom(requested: int) -> void:
	var plan: Dictionary = _view.plan if _playing else {}
	var target := clampi(
		requested,
		int(plan.get("zoom_min", -Settings.ZOOM_LIMIT)),
		int(plan.get("zoom_max", Settings.ZOOM_LIMIT))
	)
	target = clampi(target, -Settings.ZOOM_LIMIT, Settings.ZOOM_LIMIT)
	if _playing and target == _view.zoom:
		return
	if _playing:
		_view.zoom = target
	_settings.zoom = target
	print("EGGSHELL_ZOOM ", target)
	var error := Settings.save_zoom(_save_dir, target)
	if not error.is_empty():
		printerr(error)


func capture() -> void:
	await RenderingServer.frame_post_draw
	var path: String = _options.screenshot
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("EGGSHELL_SCREENSHOT ", path, " error=", error, " frame=", state.frame)
	get_tree().quit(0 if error == OK else 1)


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized:
		return
	if menu.is_open():
		var command := MenuInput.command(event, _menu_held)
		if not command.is_empty():
			get_viewport().set_input_as_handled()
			menu_command(command)
		return
	if not _playing:
		return
	if MenuInput.closed_command(event) == "open":
		get_viewport().set_input_as_handled()
		open_menu()
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


## Open the menu over the level, or the level list when no level is open.
func open_menu() -> void:
	menu.open(_menu_context(), _menu_values())
	_menu_held.clear()
	# Sounds wait with the simulation. After a goal the completion music keeps playing.
	if is_instance_valid(_audio) and not state.get("goal_reached", 0):
		_audio.process_mode = Node.PROCESS_MODE_DISABLED
	_menu_view.present(menu)
	print("EGGSHELL_MENU open ", menu.page())


func close_menu() -> void:
	menu.close()
	_menu_view.present(menu)
	_menu_held.clear()
	_suppressed = action_mask()
	if is_instance_valid(_audio):
		_audio.process_mode = Node.PROCESS_MODE_INHERIT
	print("EGGSHELL_MENU close")


## Carry out one menu command: close, back, confirm, up, down, left, right,
## page_up or page_down.
func menu_command(command: String) -> void:
	var request := {}
	match command:
		"close":
			request = menu.close_request()
		"back":
			request = menu.back()
		"confirm":
			request = menu.confirm()
		"up":
			menu.move(-1)
		"down":
			menu.move(1)
		"left":
			request = menu.adjust(-1)
		"right":
			request = menu.adjust(1)
		"page_up":
			menu.page_move(-1, _menu_view.visible_rows())
		"page_down":
			menu.page_move(1, _menu_view.visible_rows())
	_handle(request)
	if menu.is_open():
		_menu_view.present(menu)


func _on_row_clicked(index: int, right_half: bool) -> void:
	if not menu.is_open() or index >= menu.items().size():
		return
	menu.focus[menu.page()] = index
	var item: Dictionary = menu.items()[index]
	_handle(menu.adjust(1 if right_half else -1) if item.kind == "range" else menu.confirm())
	if menu.is_open():
		_menu_view.present(menu)


func _handle(request: Dictionary) -> void:
	if request.has("setting"):
		_apply_setting(request.setting, request.value)
		return
	match request.get("action", ""):
		"resume":
			close_menu()
		"restart":
			restart_level()
			close_menu()
		"save":
			save_slot("slot")
			menu.status = "Saved to slot."
		"load":
			if load_slot("slot"):
				set_physics_process(not bool(state.goal_reached))
				close_menu()
			else:
				menu.status = "No saved slot for this level."
		"next":
			_open_listed(LevelList.next_index(_levels, _level_index))
		"open_level":
			_open_listed(int(request.index))
		"quit":
			close_menu()
			notification(NOTIFICATION_WM_CLOSE_REQUEST)


## Start the open level again from its beginning, as a fresh load does.
func restart_level() -> void:
	Maps.select_map(world, int(world.initial_map))
	state = State.create(world)
	_loop.restored()
	_goal_menu_shown = false
	set_physics_process(true)
	print("EGGSHELL_RESTART ", _level_index)


func _open_listed(index: int) -> void:
	if index < 0 or index >= _levels.size():
		return
	var entry: Dictionary = _levels[index]
	var read := _read_level(entry.path)
	var built := World.build(read.code, _facts) if read.error.is_empty() else {}
	if not read.error.is_empty() or not built.ok:
		var error: String = read.error if not read.error.is_empty() else built.error
		printerr(error)
		menu.status = "Cannot open %s: %s" % [entry.file, error]
		return
	var first := not _playing
	_start_level(built.world, entry.path)
	if first and not _setup_probe():
		return
	print("EGGSHELL_START ", state.frame)
	close_menu()


func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"zoom":
			_set_zoom(int(value))
			menu.values.zoom = int(_settings.zoom)
			return
		"music_volume", "effects_volume":
			_settings[key] = int(value)
			if is_instance_valid(_audio):
				_audio.set_volumes(int(_settings.music_volume), int(_settings.effects_volume))
		"resume":
			_settings.resume = bool(value)
			_resume = _settings.resume
		"quick_death", "play_timer":
			_settings[key] = bool(value)
			_timer.visible = bool(_settings.play_timer)
	print("EGGSHELL_SETTING ", key, " ", value)
	var error := Settings.save_values(_save_dir, {key: _settings[key]})
	if not error.is_empty():
		printerr(error)
		menu.status = error


func _menu_context() -> Dictionary:
	var goal := _playing and bool(state.get("goal_reached", 0))
	return {
		"level_open": _playing,
		"goal": goal,
		"has_next": LevelList.next_index(_levels, _level_index) >= 0,
		"levels": _levels,
		"folder": _level_folder.get_file(),
		"current_level": _level_index,
		"summary": _summary() if goal else "",
	}


func _summary() -> String:
	return "Score %d. Time %s. Hurt %d, deaths %d." % [
		Life.score(state),
		Hud.clock_text(int(state.get("total_play_ticks", 0))),
		int(state.get("hits", 0)),
		int(state.get("deaths", 0))
	]


func _menu_values() -> Dictionary:
	var plan: Dictionary = _view.plan if _playing else {}
	var values := {
		"zoom": int(plan.get("zoom", _settings.zoom)),
		"zoom_min": int(plan.get("zoom_min", -Settings.ZOOM_LIMIT)),
		"zoom_max": int(plan.get("zoom_max", Settings.ZOOM_LIMIT)),
	}
	for key: String in ["music_volume", "effects_volume", "quick_death", "play_timer", "resume"]:
		values[key] = _settings[key]
	return values


func save_slot(slot: String) -> void:
	var bytes := Snapshot.encode(state)
	if bytes.is_empty():
		printerr("Save skipped: invalid snapshot state")
		return
	if slot == "slot":
		_slot_bytes = bytes
	_store.submit(_slot_dir.path_join(slot + ".egg"), bytes, state.frame)


## Restore a slot of the open level. Returns true when the state was replaced.
func load_slot(slot: String) -> bool:
	var path := _slot_dir.path_join(slot + ".egg")
	var bytes := _slot_bytes if slot == "slot" else PackedByteArray()
	if bytes.is_empty():
		if not FileAccess.file_exists(path):
			return false
		bytes = FileAccess.get_file_as_bytes(path)
	var loaded := Snapshot.decode(bytes, world.identity, world)
	if loaded.ok:
		state = loaded.state
		_loop.restored()
		print("EGGSHELL_RESUME ", slot, " ", state.frame)
		return true
	printerr("Ignoring ", slot, ": ", loaded.error)
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func _exit_tree() -> void:
	_closing = true
	if _initialized and _playing and _resume:
		save_slot("autosave")
	_store.close()
	if _profile_file != null:
		_profile_file.close()
	if _initialized:
		for result: Dictionary in _store.results():
			print("EGGSHELL_SAVE ", JSON.stringify(result))
		print("EGGSHELL_EXIT ", state.get("frame", 0))
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
		"slot_load": [],
		"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
		"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
		"zoom_reset": [KEY_0, KEY_KP_0]
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
		"slot_load": [JOY_BUTTON_RIGHT_SHOULDER],
		"zoom_reset": [JOY_BUTTON_RIGHT_STICK]
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
		# The right stick is free; a firm push zooms one step.
		var zoom := InputEventJoypadMotion.new()
		zoom.axis = JOY_AXIS_RIGHT_Y
		zoom.axis_value = direction
		InputMap.action_add_event("zoom_in" if direction < 0 else "zoom_out", zoom)
	for action: String in ["zoom_in", "zoom_out"]:
		InputMap.action_set_deadzone(action, 0.6)
	MenuInput.setup()


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
