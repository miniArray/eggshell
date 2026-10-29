extends RefCounted
## Menu input actions and the command for one input event. Keyboard and controller
## map to the same commands. Stick motion counts once per push past the dead zone.

## Command name -> [keys, controller buttons, [axis, direction] pairs].
const ACTIONS := {
	"pause": [[KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], []],
	"menu_close": [[KEY_P], [JOY_BUTTON_START], []],
	"menu_back": [[KEY_ESCAPE, KEY_BACKSPACE, KEY_X], [JOY_BUTTON_B], []],
	"menu_confirm": [[KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z], [JOY_BUTTON_A], []],
	"menu_up": [[KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1]]],
	"menu_down": [[KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1]]],
	"menu_left": [[KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1]]],
	"menu_right": [[KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1]]],
	"menu_page_up": [[KEY_PAGEUP], [JOY_BUTTON_LEFT_SHOULDER], []],
	"menu_page_down": [[KEY_PAGEDOWN], [JOY_BUTTON_RIGHT_SHOULDER], []],
}
## While the menu is open, the first matching action wins.
const ORDER := [
	["menu_close", "close"],
	["menu_back", "back"],
	["menu_confirm", "confirm"],
	["menu_up", "up"],
	["menu_down", "down"],
	["menu_left", "left"],
	["menu_right", "right"],
	["menu_page_up", "page_up"],
	["menu_page_down", "page_down"],
]
## Movement commands repeat while a key is held.
const REPEATS := ["up", "down", "left", "right", "page_up", "page_down"]
const STICK_DEADZONE := 0.5


static func setup() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, STICK_DEADZONE)
		var lists: Array = ACTIONS[action]
		for key: int in lists[0]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
		for button: int in lists[1]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
		for pair: Array in lists[2]:
			var event := InputEventJoypadMotion.new()
			event.axis = pair[0]
			event.axis_value = pair[1]
			InputMap.action_add_event(action, event)


## The command for `event` while the menu is closed: "open" or "".
static func closed_command(event: InputEvent) -> String:
	return "open" if event.is_action_pressed("pause") else ""


## The command for `event` while the menu is open, or "". `held` keeps which stick
## directions are past the dead zone, so one push gives one command.
static func command(event: InputEvent, held: Dictionary) -> String:
	if event is InputEventJoypadMotion:
		# Read the axis value directly: a centred stick must release both directions.
		var result := ""
		for pair: Array in ORDER:
			for motion: Array in ACTIONS[pair[0]][2]:
				if motion[0] != event.axis:
					continue
				var key := "%d:%s" % [event.device, pair[0]]
				var down: bool = event.axis_value * motion[1] >= STICK_DEADZONE
				if down and not held.get(key, false) and result.is_empty():
					result = pair[1]
				held[key] = down
		return result
	for pair: Array in ORDER:
		if event.is_action_pressed(pair[0], pair[1] in REPEATS):
			return pair[1]
	return ""
