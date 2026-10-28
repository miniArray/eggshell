extends SceneTree
## Input-map and replay-boundary checks; no scene or connected controller is required.
const Game = preload("res://src/view/game.gd")
const Bits = preload("res://src/sim/move_input.gd")
const ACTIONS := [
	"move_left", "move_right", "jump", "use", "move_up", "move_down", "throw", "aim_lock"
]
var checks := 0
var failures := 0


func _initialize() -> void:
	var game := Game.new()
	game.setup_input()
	game.setup_input()
	for index in ACTIONS.size():
		Input.action_press(ACTIONS[index])
		check(Game.action_mask() == 1 << index, "live input maps " + ACTIONS[index])
		Input.action_release(ACTIONS[index])
	for action: String in ACTIONS:
		Input.action_press(action)
	check(Game.action_mask() == Bits.MASK, "all eight bits remain independently reachable")
	Input.action_press("slot_modifier")
	check(Game.action_mask() == 63, "slot chord does not also throw or toggle aim")
	Input.action_release("slot_modifier")
	for action: String in ACTIONS:
		Input.action_release(action)
	check(Game.action_mask() == 0, "release clears all action bits")
	check(
		has_key("move_up", KEY_W) and has_key("move_down", KEY_S),
		"vertical keyboard bindings exist"
	)
	check(has_key("throw", KEY_C) and has_key("aim_lock", KEY_V), "aim keyboard bindings exist")
	check(
		(
			has_button("throw", JOY_BUTTON_LEFT_SHOULDER)
			and has_button("aim_lock", JOY_BUTTON_RIGHT_SHOULDER)
		),
		"shoulders expose aiming without losing slot chords"
	)
	check(
		has_axis("move_up", JOY_AXIS_LEFT_Y, -1) and has_axis("move_down", JOY_AXIS_LEFT_Y, 1),
		"vertical stick exposes both directions"
	)
	for value: Variant in [0, 15, 16, 32, 64, 128, 255, 255.0]:
		check(Game.valid_replay_mask(value), "replay accepts an exact mask: " + str(value))
	for value: Variant in [-1, 256, 0.5, true, "1", [], {}, null, NAN, INF]:
		check(not Game.valid_replay_mask(value), "replay rejects an invalid mask: " + str(value))
	game.free()
	print("MOVE_INPUT_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


static func has_key(action: String, key: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == key:
			return true
	return false


static func has_button(action: String, button: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return true
	return false


static func has_axis(action: String, axis: int, direction: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and event.axis_value == direction:
			return true
	return false


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
