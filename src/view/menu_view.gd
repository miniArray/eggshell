extends CanvasLayer
## Draws the menu model with the default font and the message panel's plain style:
## white text on black with a white border. It owns no menu state; the game moves
## the model and calls `present`. Focus is the model's, so keyboard, controller and
## mouse share one focus. Long lists scroll and keep the focused row in view.

signal row_clicked(index: int, right_half: bool)

const Model = preload("res://src/view/menu_model.gd")
const FONT_SIZE := 16
const GAP := 8
## The window size at which the menu draws at scale 1; it scales in whole steps above.
const REFERENCE := Vector2(832, 448)
const MAX_SCALE := 4
## The widest panel, in unscaled pixels, for a readable line length. Its height
## follows the content up to the window height; longer lists scroll.
const MAX_WIDTH := 480.0
## Below this many rows of list area, the folder line and the key hint move into
## the scrolling list, so a short window keeps more rows on the surface.
const MIN_LIST_ROWS := 4
const DIM := Color(0, 0, 0, 0.6)
const MUTED := Color(0.65, 0.65, 0.65)

var _root := Control.new()
var _panel := PanelContainer.new()
var _title := Label.new()
var _info := Label.new()
var _status := Label.new()
var _column := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _content := VBoxContainer.new()
var _rows := VBoxContainer.new()
var _hint := Label.new()
var _model: Model
var _built_page := ""
var _built_count := -1
var _plan := {}
var _scroll_pending := false
var _compact := false


func _init() -> void:
	layer = 10
	visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_panel.add_theme_stylebox_override("panel", _box(Color.BLACK, Color.WHITE, GAP))
	_root.add_child(_panel)
	_column.add_theme_constant_override("separation", GAP / 2)
	_panel.add_child(_column)
	for label: Label in [_title, _info, _status, _hint]:
		_style(label, Color.WHITE)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", MUTED)
	_hint.add_theme_color_override("font_color", MUTED)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", GAP / 2)
	_content.add_child(_rows)
	_scroll.add_child(_content)
	for node: Control in [_title, _info, _status, _scroll, _hint]:
		_column.add_child(node)


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)


## Show `model`, or hide when it is closed.
func present(model: Model) -> void:
	_model = model
	visible = model.is_open()
	if not visible:
		_built_page = ""
		return
	var list := model.items()
	if model.page() != _built_page or list.size() != _built_count:
		_build(list)
	_refresh(list)
	_layout()


## Rows that fit in the list area, for paging. At least 1.
func visible_rows() -> int:
	if _rows.get_child_count() == 0:
		return 1
	var row: Control = _rows.get_child(0)
	return maxi(1, floori(_scroll.size.y / maxf(1, row.size.y)))


## Panel placement for a container size: whole-number scale, centred, margins
## that shrink before the panel does.
static func plan(container: Vector2) -> Dictionary:
	if container.x <= 0 or container.y <= 0:
		return {}
	var factor := clampi(
		floori(minf(container.x / REFERENCE.x, container.y / REFERENCE.y)), 1, MAX_SCALE
	)
	var space := container / factor
	var margin := floorf(minf(2 * GAP, minf(space.x, space.y) / 16))
	var size := Vector2(minf(MAX_WIDTH, space.x - 2 * margin), space.y - 2 * margin)
	size = size.max(Vector2.ONE)
	return {"scale": factor, "size": size, "space": space}


## True when a panel of `height` keeps fewer than MIN_LIST_ROWS rows of `row`
## height after a header of `header` height.
static func compact(height: float, header: float, row: float) -> bool:
	return height - header < MIN_LIST_ROWS * row


func _build(list: Array[Dictionary]) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for index in list.size():
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.gui_input.connect(_row_input.bind(index, row))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", GAP)
		row.add_child(line)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		for name: String in ["Label", "Detail"]:
			var label := Label.new()
			label.name = name
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_style(label, Color.WHITE)
			text.add_child(label)
		var value := Label.new()
		value.name = "Value"
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_style(value, Color.WHITE)
		line.add_child(value)
		_rows.add_child(row)
	_built_page = _model.page()
	_built_count = list.size()
	_scroll.scroll_vertical = 0


func _refresh(list: Array[Dictionary]) -> void:
	_title.text = _model.title()
	_info.text = _model.info()
	_info.visible = not _info.text.is_empty()
	_status.text = _model.status
	_status.visible = not _status.text.is_empty()
	_hint.text = _model.hint()
	var focused := _model.focused()
	for index in list.size():
		var item: Dictionary = list[index]
		var row: PanelContainer = _rows.get_child(index)
		var on := index == focused
		row.add_theme_stylebox_override(
			"panel", _box(Color.WHITE if on else Color.TRANSPARENT, Color.TRANSPARENT, GAP / 2)
		)
		var color := Color.BLACK if on else (Color.WHITE if item.enabled else MUTED)
		var label: Label = row.find_child("Label", true, false)
		var detail: Label = row.find_child("Detail", true, false)
		var value: Label = row.find_child("Value", true, false)
		label.text = item.label + ("  (playing)" if item.get("current", false) else "")
		detail.text = item.detail
		detail.visible = not item.detail.is_empty()
		value.text = Model.value_text(item)
		value.visible = not value.text.is_empty()
		for node: Label in [label, detail, value]:
			node.add_theme_color_override("font_color", color)
	_scroll_pending = true


func _layout() -> void:
	if not visible:
		return
	_plan = plan(_root.get_viewport_rect().size)
	if _plan.is_empty():
		return
	_panel.scale = Vector2.ONE * _plan.scale
	# Fit the panel to its content height, up to the planned size; the list scrolls past it.
	var size := Vector2(_plan.size.x, minf(_plan.size.y, maxf(_needed(), 1)))
	_panel.size = size
	_panel.position = ((_plan.space - size) / 2).floor() * _plan.scale
	_fit.call_deferred()


## After the containers sort, wrapped rows know their height; refit.
func _fit() -> void:
	if not visible or _plan.is_empty():
		return
	var row := 2 * GAP + ceilf(ThemeDB.fallback_font.get_height(FONT_SIZE))
	if _rows.get_child_count() > 0 and _rows.get_child(0).size.y > 0:
		row = _rows.get_child(0).size.y
	var wanted := compact(_plan.size.y, _header(), row)
	if wanted != _compact:
		_set_compact(wanted)
		_fit.call_deferred()
		return
	var height := minf(_plan.size.y, _needed())
	if absf(height - _panel.size.y) >= 1:
		_panel.size.y = height
		_panel.position.y = floorf((_plan.space.y - height) / 2) * _plan.scale


## The panel height that shows every row without scrolling.
func _needed() -> float:
	return _panel.get_combined_minimum_size().y + _content.get_combined_minimum_size().y


## The height of the title, folder line, status and hint with the panel padding, as
## if none of them were in the list.
func _header() -> float:
	var height := 2.0 * GAP + 2
	for label: Label in [_title, _info, _status, _hint]:
		if label.visible:
			height += label.get_combined_minimum_size().y + GAP / 2.0
	return height


func _set_compact(on: bool) -> void:
	_compact = on
	for label: Label in [_info, _hint]:
		label.get_parent().remove_child(label)
	if on:
		_content.add_child(_info)
		_content.move_child(_info, 0)
		_content.add_child(_hint)
	else:
		_column.add_child(_info)
		_column.move_child(_info, 1)
		_column.add_child(_hint)
	_scroll_pending = true


## Bring the focused row into the list area once the rows have their sizes. Runs
## after a focus change only, so a mouse wheel can still scroll freely.
func _process(_delta: float) -> void:
	if not _scroll_pending or _model == null or not visible:
		return
	var index := _model.focused()
	if index >= _rows.get_child_count():
		return
	var row: Control = _rows.get_child(index)
	if row.size.y <= 0 or _scroll.size.y <= 0:
		return
	_scroll_pending = false
	var bottom := _rows.position.y + row.position.y + row.size.y
	# The first row also shows the folder line above it when that line is in the list.
	var top := 0.0 if index == 0 else bottom - row.size.y
	_scroll.scroll_vertical = int(
		scroll_for(top, bottom - top, float(_scroll.scroll_vertical), _scroll.size.y)
	)


## The scroll offset that shows a row from `top` to `top + height` in a list area
## of `area` height, moving as little as possible from `current`.
static func scroll_for(top: float, height: float, current: float, area: float) -> float:
	if top < current or height >= area:
		return top
	if top + height > current + area:
		return top + height - area
	return current


func _row_input(event: InputEvent, index: int, row: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		row.accept_event()
		row_clicked.emit(index, event.position.x > row.size.x / 2)


static func _style(label: Label, color: Color) -> void:
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)


static func _box(fill: Color, border: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_content_margin_all(padding)
	return box
