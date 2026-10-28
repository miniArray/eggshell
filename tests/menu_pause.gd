extends SceneTree
## The real game composition with the pause menu. Opening, navigating, changing
## settings and closing the menu must leave the snapshot bytes unchanged, and no
## step may run while it is open. Uses the original test courses as a level folder,
## placeholder graphics and no audio. Input arrives as viewport events.
const Game = preload("res://src/view/game.gd")
const Menu = preload("res://src/view/menu_model.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Settings = preload("res://src/save/settings.gd")
const COURSES := ["stride", "actors"]
var _checks := 0
var _failures := 0
var _game: Node
var _base := "/tmp/eggshell-menu-pause-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var folder := _base.path_join("levels")
	DirAccess.make_dir_recursive_absolute(folder)
	for index in COURSES.size():
		var code := FileAccess.get_file_as_string("res://tests/fixtures/%s.level.json" % COURSES[index])
		var file := FileAccess.open(folder.path_join("%d-%s.json" % [index + 1, COURSES[index]]), FileAccess.WRITE)
		file.store_string(code)
		file.close()
	# The reference window, so the zoom setting has room to change.
	root.size = Vector2i(832, 448)
	_game = Game.new()
	_game.launch_options = {
		"levels": folder,
		"level-code": folder.path_join("1-stride.json"),
		"save-dir": _base.path_join("save"),
		"placeholder": "true",
		"mute": "true",
		"smooth": "off"
	}
	root.add_child(_game)
	await frames(10)
	check(_game.state.frame > 0, "The level steps before the menu opens")
	await pause_checks()
	await action_checks(folder)
	_game.queue_free()
	await frames(2)
	for path: String in [
		"levels/1-stride.json", "levels/2-actors.json", "save/settings.json", "save/settings.json.tmp"
	]:
		DirAccess.remove_absolute(_base.path_join(path))
	print("MENU_PAUSE_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func pause_checks() -> void:
	press(KEY_ESCAPE)
	await frames(1)
	check(_game.menu.is_open() and _game.menu.page() == Menu.MAIN, "Escape opens the pause menu")
	var frame: int = _game.state.frame
	var bytes := Snapshot.encode(_game.state)
	var keys := [
		KEY_DOWN, KEY_DOWN, KEY_UP,  # Move through the main page.
		KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_ENTER,  # Open Settings.
		KEY_LEFT, KEY_RIGHT, KEY_RIGHT,  # Zoom.
		KEY_DOWN, KEY_LEFT, KEY_DOWN, KEY_RIGHT,  # Music and effects volume.
		KEY_DOWN, KEY_ENTER, KEY_DOWN, KEY_ENTER,  # Quick death and play timer on.
		KEY_ESCAPE,  # Back to the main page.
		KEY_UP, KEY_ENTER, KEY_PAGEDOWN, KEY_PAGEUP, KEY_DOWN, KEY_BACKSPACE  # The level list.
	]
	var pages := {}
	for code: int in keys:
		press(code)
		pages[_game.menu.page()] = true
		await frames(2)
		check(_game.state.frame == frame, "No step runs while the menu is open (%d)" % code)
	check(pages.has(Menu.SETTINGS) and pages.has(Menu.LEVELS), "Navigation reached both pages")
	check(Snapshot.encode(_game.state) == bytes, "Menu navigation leaves the state bytes unchanged")
	var saved := Settings.read_or_create(_base.path_join("save"))
	check(saved.quick_death and saved.play_timer, "Menu settings are saved")
	check(saved.music_volume == 70 and saved.effects_volume == 90, "Volumes are saved")
	check(_game.menu.is_open() and _game.menu.page() == Menu.MAIN, "Back returns to the main page")
	check(_game.get("_settings").zoom == 2, "Zoom changed in the menu: %s" % _game.menu.values)
	press(KEY_P)
	check(not _game.menu.is_open(), "P closes the menu")
	check(Snapshot.encode(_game.state) == bytes, "Closing the menu leaves the state bytes unchanged")
	await frames(5)
	check(_game.state.frame > frame, "Steps resume after the menu closes")
	check(_game.state.quick_death == 1, "Quick death reaches play at the next step")
	press(KEY_ESCAPE, JOY_BUTTON_START)
	await frames(1)
	check(_game.menu.is_open(), "Controller Start opens the menu")
	frame = _game.state.frame
	bytes = Snapshot.encode(_game.state)
	press(KEY_NONE, JOY_BUTTON_DPAD_DOWN)
	press(KEY_NONE, JOY_BUTTON_DPAD_UP)
	await frames(3)
	check(_game.state.frame == frame, "No step ran while the controller used the menu")
	press(KEY_NONE, JOY_BUTTON_B)
	check(not _game.menu.is_open(), "Controller B at the main page resumes")
	check(Snapshot.encode(_game.state) == bytes, "Controller navigation leaves bytes unchanged")


func action_checks(folder: String) -> void:
	# Save, then load, from the menu: the slot belongs to this level.
	_game.open_menu()
	select("save")
	check(_game.menu.status == "Saved to slot.", "Save to slot reports success")
	var slot := Snapshot.encode(_game.state)
	select("resume")
	await frames(5)
	check(Snapshot.encode(_game.state) != slot, "Play continues after saving")
	_game.open_menu()
	select("load")
	check(not _game.menu.is_open(), "Load from slot closes the menu")
	check(Snapshot.encode(_game.state) == slot, "Load from slot restores the saved bytes")
	_game.open_menu()
	select("restart")
	check(_game.state.frame == 0 and not _game.menu.is_open(), "Restart level starts over")
	var first: String = _game.world.identity
	_game.open_menu()
	select("levels")
	check(_game.menu.page() == Menu.LEVELS and _game.menu.focused() == 0, "The list shows the level")
	check(_game.menu.items()[1].label == "Actors", "Rows use the level name")
	_game.menu.move(1)
	_game.menu_command("confirm")
	check(not _game.menu.is_open() and _game.world.identity != first, "A listed level opens")
	await frames(3)
	check(_game.state.frame > 0, "The new level steps")
	_game.open_menu()
	select("load")
	check(_game.menu.status.begins_with("No saved slot"), "The slot is per level")
	select("levels")
	_game.menu_command("up")
	_game.menu_command("confirm")
	check(_game.world.identity == first, "The first level opens again from the list")
	await frames(2)
	_game.open_menu()
	select("load")
	check(Snapshot.encode(_game.state) == slot, "The first level kept its own slot")
	var level_dir := _base.path_join("save/levels").path_join(first)
	await frames(2)
	check(FileAccess.file_exists(level_dir.path_join("slot.egg")), "Folder levels save per level")
	check(not FileAccess.file_exists(_base.path_join("save/slot.egg")), "No shared slot file")


## Focus the item `id` on the current page and confirm it.
func select(id: String) -> void:
	var items: Array = _game.menu.items()
	for index in items.size():
		if items[index].id == id:
			_game.menu.focus[_game.menu.page()] = index
			_game.menu_command("confirm")
			return
	check(false, "Menu item %s exists on %s" % [id, _game.menu.page()])


func press(code: int, button := -1) -> void:
	var event: InputEvent
	if button >= 0:
		event = InputEventJoypadButton.new()
		event.button_index = button
	else:
		event = InputEventKey.new()
		event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var release: InputEvent = event.duplicate()
	release.pressed = false
	root.push_input(release)


func frames(count: int) -> void:
	for index in count:
		await physics_frame


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
