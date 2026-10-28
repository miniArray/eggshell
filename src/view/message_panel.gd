extends Control
## Plain read-only modal text. All input and page state stays in the simulation.
const Block = preload("res://src/sim/types/item_block.gd")
# Keep the message reference area and the existing HUD font/spacing sizes.
const CONTENT := Vector2(304, 168)
const GAP := 8
const FONT_SIZE := 16
const SIZE := Vector2(320, 216)
var _body := Control.new()
var _text := Label.new()
var _hint := Label.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.clip_contents = true
	_body.position = Vector2.ONE * GAP
	_body.size = CONTENT
	add_child(_body)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label: Label in [_text, _hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", ThemeDB.fallback_font)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
	_body.add_child(_text)
	_hint.position = Vector2(GAP, CONTENT.y + 2 * GAP)
	_hint.size = Vector2(CONTENT.x, FONT_SIZE)
	add_child(_hint)
	size = SIZE


static func plan(container: Vector2, hud_bottom: float) -> Dictionary:
	if container.x <= 0 or container.y <= 0:
		return {}
	var top := minf(hud_bottom + GAP, container.y * 0.4)
	var available := Vector2(container.x, container.y - top)
	var factor := 1.0
	while SIZE.x * factor > available.x or SIZE.y * factor > available.y:
		factor /= 2.0
	return {
		"scale": factor,
		"position": Vector2(0, top) + (available - SIZE * factor) / 2.0,
		"size": SIZE * factor
	}


func present(state: Dictionary, world: Dictionary, container: Vector2, hud_bottom: float) -> void:
	var message := Block.message_state(state, world)
	var layout := plan(container, hud_bottom)
	visible = not message.is_empty() and not layout.is_empty()
	if not visible:
		return
	position = layout.position
	scale = Vector2.ONE * layout.scale
	_text.text = Block.message(state, world)
	_text.size = Vector2(CONTENT.x, 0)
	_text.size.y = maxf(CONTENT.y, _text.get_minimum_size().y)
	var page: int = clampi(message.section, 0, message.sections - 1)
	var fraction := float(page) / maxi(1, message.sections - 1)
	_text.position.y = -maxf(0, _text.size.y - CONTENT.y) * fraction
	_hint.text = "%d/%d  Up/Down: page  Throw: close" % [page + 1, message.sections]
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color.BLACK)
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color.WHITE, false)
