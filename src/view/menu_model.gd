extends RefCounted
## Pause, settings and level-list menu state. Pure data: no nodes, input devices,
## files or play state. The game reads the returned requests and carries them out.
##
## A request is {} (nothing to do), {"action": id, ...} or {"setting": key, "value": v}.

const START := "start"
const MAIN := "main"
const SETTINGS := "settings"
const LEVELS := "levels"
const VOLUME_STEP := 10

## Open pages, root first. Empty while the menu is closed.
var pages: Array[String] = []
## The focused item index for each page.
var focus := {}
## {"level_open", "goal", "has_next", "levels", "folder", "current_level", "summary"}
var context := {}
## Setting values shown in the menu: zoom, zoom_min, zoom_max, music_volume,
## effects_volume, quick_death, play_timer, resume.
var values := {}
## One line of feedback, such as "Saved to slot". Cleared when the page changes.
var status := ""


## Open the menu. Without an open level the root is the start page with the list on top.
func open(menu_context: Dictionary, setting_values: Dictionary) -> void:
	context = menu_context
	values = setting_values.duplicate()
	focus = {}
	status = ""
	if context.get("level_open", false):
		pages = [MAIN]
	else:
		pages = [START]
		if not context.get("levels", []).is_empty():
			_push(LEVELS)


func close() -> void:
	pages = []
	status = ""


func is_open() -> bool:
	return not pages.is_empty()


func page() -> String:
	return pages.back() if is_open() else ""


func title() -> String:
	match page():
		START:
			return "Eggshell"
		MAIN:
			return "Level complete" if context.get("goal", false) else "Paused"
		SETTINGS:
			return "Settings"
		LEVELS:
			return "Levels"
	return ""


## Readout text under the title: the score after a goal, or the folder for the list.
func info() -> String:
	match page():
		MAIN:
			return str(context.get("summary", "")) if context.get("goal", false) else ""
		LEVELS:
			var count: int = context.get("levels", []).size()
			return (
				"%s, %d %s"
				% [str(context.get("folder", "")), count, "level" if count == 1 else "levels"]
			)
		START:
			return "No level is open."
	return ""


## Controls for the current page, in plain words.
func hint() -> String:
	match page():
		SETTINGS:
			return "Left/Right: change. Enter or A: select. Esc or B: back."
		LEVELS:
			return "Enter or A: play. PgUp/PgDn or shoulders: page. Esc or B: back."
		MAIN:
			if context.get("goal", false):
				return "Enter or A: select. Esc or B: close."
			return "Enter or A: select. Esc or B: resume."
	return "Enter or A: select."


func items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match page():
		START:
			if not context.get("levels", []).is_empty():
				result.append(_item("levels", "Levels", "page"))
			result.append(_item("settings", "Settings", "page"))
			result.append(_item("quit", "Quit", "action"))
		MAIN:
			if not context.get("goal", false):
				result.append(_item("resume", "Resume", "action"))
			elif context.get("has_next", false):
				result.append(_item("next", "Next level", "action"))
			result.append(_item("restart", "Restart level", "action"))
			result.append(_item("save", "Save to slot", "action"))
			result.append(_item("load", "Load from slot", "action"))
			if not context.get("levels", []).is_empty():
				result.append(_item("levels", "Levels", "page"))
			result.append(_item("settings", "Settings", "page"))
			result.append(_item("quit", "Quit", "action"))
		SETTINGS:
			result.append(
				_range(
					"zoom",
					"Zoom",
					int(values.get("zoom_min", 0)),
					int(values.get("zoom_max", 0)),
					1
				)
			)
			result.append(_range("music_volume", "Music volume", 0, 100, VOLUME_STEP))
			result.append(_range("effects_volume", "Effects volume", 0, 100, VOLUME_STEP))
			result.append(_toggle("quick_death", "Quick death"))
			result.append(_toggle("play_timer", "Play timer"))
			result.append(_toggle("resume", "Resume where I left off"))
			result.append(_item("back", "Back", "action"))
		LEVELS:
			var levels: Array = context.get("levels", [])
			for index in levels.size():
				var level: Dictionary = levels[index]
				var item := _item("level", level.name, "level")
				item.index = index
				item.enabled = level.ok
				item.current = index == int(context.get("current_level", -1))
				item.detail = (
					("by " + level.author if not level.author.is_empty() else "")
					if level.ok
					else level.error
				)
				item.file = level.file
				result.append(item)
	return result


func focused() -> int:
	var count := items().size()
	return clampi(int(focus.get(page(), 0)), 0, maxi(0, count - 1))


## Move the focus by `delta` items, wrapping at either end.
func move(delta: int) -> void:
	var count := items().size()
	if count > 0:
		focus[page()] = posmod(focused() + delta, count)


## Move the focus by whole pages of `rows` items, stopping at either end.
func page_move(delta: int, rows: int) -> void:
	var count := items().size()
	if count > 0:
		focus[page()] = clampi(focused() + delta * maxi(1, rows), 0, count - 1)


## Change the focused setting by one step. Returns a setting request or {}.
func adjust(delta: int) -> Dictionary:
	var list := items()
	if list.is_empty() or delta == 0:
		return {}
	var item: Dictionary = list[focused()]
	match item.kind:
		"toggle":
			return _change(item.id, not bool(item.value))
		"range":
			var value := clampi(int(item.value) + delta * int(item.step), item.min, item.max)
			if value != int(item.value):
				return _change(item.id, value)
	return {}


## Choose the focused item. Returns a request or {}.
func confirm() -> Dictionary:
	var list := items()
	if list.is_empty():
		return {}
	var item: Dictionary = list[focused()]
	var request := {}
	match item.kind:
		"page":
			_push(item.id)
		"toggle":
			request = _change(item.id, not bool(item.value))
		"level":
			if item.enabled:
				request = {"action": "open_level", "index": item.index}
			else:
				status = "Cannot open %s: %s" % [item.file, item.detail]
		"action":
			request = back() if item.id == "back" else {"action": item.id}
	return request


## Go back one page. At the main page this asks to resume.
func back() -> Dictionary:
	if pages.size() > 1:
		pages.pop_back()
		status = ""
		return {}
	return close_request()


## Leave the menu from any page. Without an open level there is nothing to resume.
func close_request() -> Dictionary:
	return {"action": "resume"} if context.get("level_open", false) else {}


## Text for an item's value, or "" for an action.
static func value_text(item: Dictionary) -> String:
	match item.kind:
		"toggle":
			return "On" if item.value else "Off"
		"range":
			var number := (
				"%+d" % item.value if item.id == "zoom" and item.value != 0 else str(item.value)
			)
			return (
				"%s %s %s"
				% [
					"<" if item.value > item.min else " ",
					number,
					">" if item.value < item.max else " "
				]
			)
	return ""


func _push(id: String) -> void:
	pages.append(id)
	status = ""
	if id == LEVELS and not focus.has(LEVELS):
		focus[LEVELS] = maxi(0, int(context.get("current_level", 0)))


func _change(key: String, value: Variant) -> Dictionary:
	values[key] = value
	return {"setting": key, "value": value}


func _item(id: String, label: String, kind: String) -> Dictionary:
	return {"id": id, "label": label, "kind": kind, "enabled": true, "detail": ""}


func _toggle(id: String, label: String) -> Dictionary:
	var item := _item(id, label, "toggle")
	item.value = bool(values.get(id, false))
	return item


func _range(id: String, label: String, low: int, high: int, step: int) -> Dictionary:
	var item := _item(id, label, "range")
	item.min = mini(low, high)
	item.max = maxi(low, high)
	item.step = step
	item.value = clampi(int(values.get(id, 0)), item.min, item.max)
	return item
