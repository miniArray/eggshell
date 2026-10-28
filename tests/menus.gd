extends SceneTree
## Fast menu checks with invented data: menu state, level-list parsing, settings,
## input commands and layout plans. No game scene, level or graphics pack.
const Menu = preload("res://src/view/menu_model.gd")
const MenuView = preload("res://src/view/menu_view.gd")
const MenuInput = preload("res://src/view/menu_input.gd")
const LevelList = preload("res://src/view/level_list.gd")
const PlayTimer = preload("res://src/view/play_timer.gd")
const Settings = preload("res://src/save/settings.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	model_checks()
	settings_page_checks()
	level_page_checks()
	level_list_checks()
	settings_checks()
	input_checks()
	layout_checks()
	print("MENUS_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


static func values() -> Dictionary:
	return {
		"zoom": 0,
		"zoom_min": -1,
		"zoom_max": 2,
		"music_volume": 80,
		"effects_volume": 75,
		"quick_death": false,
		"play_timer": false,
		"resume": true
	}


static func ids(model: Menu) -> Array:
	return model.items().map(func(item: Dictionary) -> String: return item.id)


static func level(name: String, ok := true) -> Dictionary:
	return {
		"path": "/levels/%s.json" % name, "file": name + ".json", "name": name,
		"author": "Ann" if ok else "", "ok": ok, "error": "" if ok else "Not a level code"
	}


func model_checks() -> void:
	var model := Menu.new()
	check(not model.is_open() and model.items().is_empty(), "A new menu is closed")
	model.open({"level_open": true}, values())
	check(model.page() == Menu.MAIN and model.title() == "Paused", "Pause opens the main page")
	check(
		ids(model) == ["resume", "restart", "save", "load", "settings", "quit"],
		"Main page items without a level folder"
	)
	check(model.confirm() == {"action": "resume"}, "Resume is focused first")
	model.move(-1)
	check(model.items()[model.focused()].id == "quit", "Moving up from the top wraps")
	model.move(1)
	model.move(1)
	check(model.confirm() == {"action": "restart"}, "Restart level")
	model.move(1)
	check(model.confirm() == {"action": "save"}, "Save to slot")
	model.move(1)
	check(model.confirm() == {"action": "load"}, "Load from slot")
	check(model.back() == {"action": "resume"}, "Back at the main page resumes")
	check(model.close_request() == {"action": "resume"}, "Close resumes from the main page")
	model.close()
	check(not model.is_open(), "Close empties the pages")
	var levels := [level("a"), level("b")]
	model.open(
		{"level_open": true, "goal": true, "has_next": true, "levels": levels, "summary": "Score 3."},
		values()
	)
	check(model.title() == "Level complete" and model.info() == "Score 3.", "Goal title and score")
	check(
		ids(model) == ["next", "restart", "save", "load", "levels", "settings", "quit"],
		"After a goal: Next level first, no Resume, and the level list"
	)
	check(model.confirm() == {"action": "next"}, "Next level is focused after a goal")
	model.open({"level_open": true, "goal": true, "has_next": false, "levels": levels}, values())
	check(ids(model)[0] == "restart", "The last level in a folder has no Next level")
	model.open({"level_open": false, "levels": levels, "current_level": -1}, values())
	check(model.pages == [Menu.START, Menu.LEVELS], "Without a level the list opens over the start")
	check(model.close_request().is_empty(), "Without a level the menu cannot close")
	model.back()
	check(ids(model) == ["levels", "settings", "quit"], "The start page offers list, settings, quit")
	check(model.back().is_empty() and model.is_open(), "Back at the start page stays open")
	model.open({"level_open": false}, values())
	check(ids(model) == ["settings", "quit"], "No folder and no level: settings and quit")


func settings_page_checks() -> void:
	var model := Menu.new()
	model.open({"level_open": true}, values())
	model.focus[Menu.MAIN] = ids(model).find("settings")
	check(model.confirm().is_empty() and model.page() == Menu.SETTINGS, "Settings opens a page")
	check(model.status.is_empty(), "Opening a page clears the status")
	check(
		ids(model)
		== [
			"zoom", "music_volume", "effects_volume", "quick_death", "play_timer", "resume", "back"
		],
		"Settings page items"
	)
	check(model.adjust(-1) == {"setting": "zoom", "value": -1}, "Zoom steps down")
	check(model.adjust(-1).is_empty(), "Zoom stops at the container's limit")
	check(Menu.value_text(model.items()[0]) == "  -1 >", "Zoom at its lower limit shows one arrow")
	model.move(1)
	check(model.adjust(1) == {"setting": "music_volume", "value": 90}, "Music volume steps by 10")
	check(model.adjust(1) == {"setting": "music_volume", "value": 100}, "Music reaches 100")
	check(model.adjust(1).is_empty(), "Music stops at 100")
	model.move(1)
	check(model.adjust(-1) == {"setting": "effects_volume", "value": 65}, "Effects from 75 to 65")
	model.move(1)
	check(model.confirm() == {"setting": "quick_death", "value": true}, "Quick death turns on")
	check(Menu.value_text(model.items()[3]) == "On", "Toggle text follows the value")
	check(model.adjust(1) == {"setting": "quick_death", "value": false}, "Right also toggles")
	model.move(1)
	check(model.confirm() == {"setting": "play_timer", "value": true}, "Play timer turns on")
	model.move(1)
	check(model.confirm() == {"setting": "resume", "value": false}, "Resume setting turns off")
	model.move(1)
	check(model.confirm().is_empty() and model.page() == Menu.MAIN, "Back item returns to main")
	check(model.items()[model.focused()].id == "settings", "Main keeps its focus after a page")
	check(model.values.music_volume == 100, "The model keeps changed values")


func level_page_checks() -> void:
	var levels := []
	for index in 30:
		levels.append(level("level %02d" % index, index != 4))
	var model := Menu.new()
	model.open({"level_open": true, "levels": levels, "current_level": 7, "folder": "pack"}, values())
	model.focus[Menu.MAIN] = ids(model).find("levels")
	model.confirm()
	check(model.page() == Menu.LEVELS and model.focused() == 7, "The list opens at the playing level")
	check(model.info() == "pack, 30 levels", "The list names the folder and count")
	check(model.items()[7].current and not model.items()[6].current, "The playing level is marked")
	check(model.items()[0].detail == "by Ann", "A level row shows its author")
	check(model.confirm() == {"action": "open_level", "index": 7}, "Confirm opens the level")
	model.page_move(1, 10)
	check(model.focused() == 17, "Page down moves by the visible rows")
	model.page_move(1, 10)
	model.page_move(1, 10)
	check(model.focused() == 29, "Page down stops at the end")
	model.page_move(-1, 100)
	check(model.focused() == 0, "Page up stops at the start")
	model.move(4)
	check(model.confirm().is_empty(), "An unreadable level does not open")
	check(model.status.contains("Not a level code"), "It says why")
	check(not model.items()[4].enabled, "An unreadable level is shown disabled")
	model.back()
	check(model.page() == Menu.MAIN and model.status.is_empty(), "Back leaves the list")


func level_list_checks() -> void:
	var good := JSON.stringify({"name": "Hill run", "author": "Bo", "maps": {"map1": {}}})
	var entry := LevelList.entry("/x/b.json", good)
	check(entry.ok and entry.name == "Hill run" and entry.author == "Bo", "Name and author")
	check(entry.file == "b.json" and entry.path == "/x/b.json", "File name and path")
	entry = LevelList.entry("/x/c.json", JSON.stringify({"name": "", "author": 0, "maps": {}}))
	check(entry.ok and entry.name == "c.json" and entry.author.is_empty(), "Name falls back to file")
	entry = LevelList.entry("/x/d.json", JSON.stringify({"name": "A\nB", "author": 12, "maps": {}}))
	check(entry.name == "A B" and entry.author == "12", "Line breaks and numeric authors")
	entry = LevelList.entry("/x/e.json", JSON.stringify({"name": 5, "maps": {}}))
	check(entry.name == "5" and entry.author.is_empty(), "A numeric name and absent author")
	var cut := "{\"name\":\"Cut\",\"author\":\"Ed\",\"maps\":{\"map1\":{\"wid"
	entry = LevelList.entry("/x/g.json", cut)
	check(entry.ok and entry.name == "Cut" and entry.author == "Ed", "The start of a file is enough")
	var late := JSON.stringify({"maps": {}, "name": "Late", "author": "Fy"})
	check(LevelList.header(late) == null, "Maps before the name needs the whole file")
	check(LevelList.entry("/x/h.json", late).name == "Late", "A late name is still found")
	var quoted := JSON.stringify({"name": "Q", "desc": "see \"maps\": here", "maps": {}})
	check(LevelList.entry("/x/i.json", quoted).name == "Q", "A quoted key in text is not a key")
	for bad: String in ["", "{", "[]", "{\"name\": \"x\"}"]:
		entry = LevelList.entry("/x/f.json", bad)
		check(not entry.ok and entry.name == "f.json" and not entry.error.is_empty(), "Bad: " + bad)
	var levels := [level("a"), level("b", false), level("c"), level("d", false)]
	check(LevelList.next_index(levels, 0) == 2, "Next skips an unreadable level")
	check(LevelList.next_index(levels, 2) == -1, "No next level after the last readable one")
	check(LevelList.next_index(levels, -1) == -1, "A level outside the folder has no next")
	check(LevelList.find(levels, "/levels/c.json") == 2, "Find by path")
	check(LevelList.find(levels, "/levels/./c.json") == 2, "Find by an equivalent path")
	check(LevelList.find(levels, "/other/c.json") == -1, "A path outside the folder")
	var directory := "/tmp/eggshell-menus-levels-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var files := {
		"level10.json": good,
		"level2.json": JSON.stringify({"name": "Two", "author": "Cy", "maps": {}}),
		"Level1.TXT": JSON.stringify({"name": "One", "author": "Di", "maps": {}}),
		"broken.json": "{",
		"notes.md": "not listed",
		".hidden.json": good
	}
	for file: String in files:
		var handle := FileAccess.open(directory.path_join(file), FileAccess.WRITE)
		handle.store_string(files[file])
		handle.close()
	var scanned := LevelList.scan(directory)
	var names: Array = scanned.levels.map(func(item: Dictionary) -> String: return item.file)
	check(
		scanned.ok and names == ["broken.json", "Level1.TXT", "level2.json", "level10.json"],
		"A folder lists level files in natural name order: %s" % [names]
	)
	check(not scanned.levels[0].ok and scanned.levels[1].name == "One", "Scan keeps bad files")
	check(not LevelList.scan(directory.path_join("missing")).ok, "A missing folder is an error")
	for file: String in files:
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)


func settings_checks() -> void:
	var directory := "/tmp/eggshell-menus-settings-%d" % OS.get_process_id()
	var path := directory.path_join("settings.json")
	var created := Settings.read_or_create(directory)
	check(
		created.error.is_empty() and not created.quick_death and not created.play_timer,
		"New settings keep quick death and the play timer off"
	)
	check(Settings.save_values(directory, {"quick_death": true}).is_empty(), "Quick death saves")
	check(Settings.save_values(directory, {"play_timer": true, "music_volume": 30}).is_empty(), "Two")
	check(Settings.save_values(directory, {"resume": false}).is_empty(), "Resume saves")
	var saved := Settings.read_or_create(directory)
	check(
		(
			saved.quick_death
			and saved.play_timer
			and saved.music_volume == 30
			and not saved.resume
			and saved.effects_volume == 80
		),
		"Saved values keep each other"
	)
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(stored.resume_where_i_left_off == false, "Resume uses its file key")
	for bad: Dictionary in [
		{"quick_death": 1}, {"music_volume": 101}, {"zoom": true}, {"colour": 1}, {"resume": "no"}
	]:
		check(not Settings.save_values(directory, bad).is_empty(), "Rejected: %s" % [bad])
	check(Settings.read_or_create(directory).music_volume == 30, "A rejected change writes nothing")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(
		JSON.stringify({"version": 1, "resume_where_i_left_off": true, "play_timer": "yes"})
	)
	file.close()
	var invalid := Settings.read_or_create(directory)
	check(
		not invalid.play_timer and invalid.error.contains("play_timer") and invalid.resume,
		"An invalid flag uses its default and keeps the rest"
	)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func input_checks() -> void:
	MenuInput.setup()
	var held := {}
	check(MenuInput.closed_command(key(KEY_ESCAPE)) == "open", "Escape opens the menu")
	check(MenuInput.closed_command(key(KEY_P)) == "open", "P opens the menu")
	check(MenuInput.closed_command(button(JOY_BUTTON_START)) == "open", "Start opens the menu")
	check(MenuInput.closed_command(key(KEY_SPACE)).is_empty(), "Jump does not open the menu")
	var expected := {
		"back": [key(KEY_ESCAPE), key(KEY_BACKSPACE), button(JOY_BUTTON_B)],
		"close": [key(KEY_P), button(JOY_BUTTON_START)],
		"confirm": [key(KEY_ENTER), key(KEY_SPACE), key(KEY_Z), button(JOY_BUTTON_A)],
		"up": [key(KEY_UP), key(KEY_W), button(JOY_BUTTON_DPAD_UP)],
		"down": [key(KEY_DOWN), key(KEY_S), button(JOY_BUTTON_DPAD_DOWN)],
		"left": [key(KEY_LEFT), button(JOY_BUTTON_DPAD_LEFT)],
		"right": [key(KEY_RIGHT), button(JOY_BUTTON_DPAD_RIGHT)],
		"page_up": [key(KEY_PAGEUP), button(JOY_BUTTON_LEFT_SHOULDER)],
		"page_down": [key(KEY_PAGEDOWN), button(JOY_BUTTON_RIGHT_SHOULDER)]
	}
	for command: String in expected:
		for event: InputEvent in expected[command]:
			check(MenuInput.command(event, held) == command, "%s from %s" % [command, event])
	var repeat := key(KEY_DOWN)
	repeat.echo = true
	check(MenuInput.command(repeat, held) == "down", "A held arrow repeats")
	var again := key(KEY_ENTER)
	again.echo = true
	check(MenuInput.command(again, held).is_empty(), "A held confirm does not repeat")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_Y, 0.9), held) == "down", "Stick push moves")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_Y, 1.0), held).is_empty(), "Held stick: once")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_Y, 0.0), held).is_empty(), "Centre releases")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_Y, -0.8), held) == "up", "Stick up moves")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_Y, 0.9), held) == "down", "Straight to down")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_X, 0.3), held).is_empty(), "Dead zone ignored")
	check(MenuInput.command(stick(JOY_AXIS_LEFT_X, -0.7), held) == "left", "Stick left adjusts")


static func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


static func button(index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


static func stick(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func layout_checks() -> void:
	# Menu panel: whole-number scale, never below 1, never wider than the container.
	var sizes := [
		Vector2(832, 448),
		Vector2(1920, 1080),
		Vector2(3840, 2160),
		Vector2(320, 1000),
		Vector2(1600, 180),
		Vector2(160, 120),
		Vector2(831, 447),
		Vector2(1664, 896),
		Vector2(1663, 896)
	]
	for size: Vector2 in sizes:
		var plan := MenuView.plan(size)
		var drawn: Vector2 = plan.size * plan.scale
		check(plan.scale >= 1 and plan.scale == floorf(plan.scale), "Whole scale at %s" % size)
		check(drawn.x <= size.x and drawn.y <= size.y, "The panel fits at %s" % size)
	check(MenuView.plan(Vector2(1663, 896)).scale == 1, "Scale 2 needs twice the reference width")
	check(MenuView.plan(Vector2(1664, 896)).scale == 2, "Scale 2 at twice the reference")
	check(MenuView.plan(Vector2(3840, 2160)).scale == 4, "Scale is at most 4")
	check(MenuView.plan(Vector2(832, 448)).size == Vector2(480, 416), "Full panel at reference")
	check(MenuView.plan(Vector2(360, 640)).size == Vector2(328, 608), "A tall window gives height")
	check(MenuView.compact(150, 120, 31) and not MenuView.compact(416, 120, 31), "Compact header")
	check(MenuView.scroll_for(0, 30, 50, 100) == 0, "Scroll up to a row above the area")
	check(MenuView.scroll_for(140, 30, 50, 100) == 70, "Scroll down to a row below the area")
	check(MenuView.scroll_for(60, 30, 50, 100) == 50, "A visible row does not scroll")
	check(MenuView.plan(Vector2(160, 120)).size.x == 146, "A tiny window keeps a small margin")
	check(MenuView.plan(Vector2.ZERO).is_empty(), "No plan for an empty container")
	# Play timer: three rows when height allows, one row when short, smaller only last.
	var widths: Array[float] = [150.0, 140.0, 140.0]
	var tall := PlayTimer.plan(Vector2(832, 448), widths, 23)
	check(tall.stacked and tall.scale == 1, "Three timer rows at the reference size")
	var bottom: Vector2 = tall.positions[2]
	check(bottom.y + tall.row <= 448, "The timer stays inside the container")
	var strip := PlayTimer.plan(Vector2(1600, 180), widths, 23)
	check(not strip.stacked and strip.scale == 1, "One timer row in a wide short strip")
	var narrow := PlayTimer.plan(Vector2(300, 200), widths, 23)
	check(narrow.scale < 1, "A small window shrinks the timer only after reflow fails")
	var big := PlayTimer.plan(Vector2(1664, 896), widths, 23)
	check(big.stacked and big.scale == 2, "The timer scales up with the container like the HUD")
	var lines := PlayTimer.lines({"attempt_ticks": 90, "play_ticks": 3600, "total_play_ticks": 0})
	check(
		lines == ["Attempt 00:00:01.50", "Level 00:01:00.00", "Total 00:00:00.00"],
		"Timer text: %s" % [lines]
	)
