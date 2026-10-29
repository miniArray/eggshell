extends Node2D
## Optional play timer readout in the lower left corner. It reads the three saved
## clocks and never writes play state. Default font, white text on black backing.

const Hud = preload("res://src/view/hud.gd")
const FONT_SIZE := 16
const GAP := 8
const PADDING := 2
## The timer may use at most this share of the container height.
const HEIGHT_SHARE := 0.25
## [label, state field]: attempt time, checkpoint-adjusted level time, total time.
const CLOCKS := [
	["Attempt", "attempt_ticks"], ["Level", "play_ticks"], ["Total", "total_play_ticks"]
]

var _font: Font = ThemeDB.fallback_font
var _lines: Array[String] = []
var _plan := {}


func _init() -> void:
	z_index = 90


static func lines(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for clock: Array in CLOCKS:
		result.append("%s %s" % [clock[0], Hud.clock_text(int(state.get(clock[1], 0)))])
	return result


## Rows for a container size. Height decides the structure: three rows while they
## fit in HEIGHT_SHARE, else one row; only then a smaller scale.
static func plan(container: Vector2, widths: Array[float], line_height: float) -> Dictionary:
	if container.x <= 0 or container.y <= 0 or widths.is_empty():
		return {}
	var row := line_height + 2 * PADDING
	var stacked := 0.0
	var inline := 0.0
	for width in widths:
		stacked = maxf(stacked, width)
		inline += width
	inline += GAP * (widths.size() - 1)
	# Whole steps up with the container like the HUD, then halvings below 1.
	var largest := clampi(floori(minf(container.x / 832, container.y / 448)), 1, 4)
	var choices: Array[float] = []
	for step in range(largest, 0, -1):
		choices.append(float(step))
	choices.append_array([0.5, 0.25])
	for factor in choices:
		var room := container / factor
		var margin := minf(GAP, minf(room.x, room.y) / 16)
		var tall := widths.size() * row + margin
		if tall <= room.y * HEIGHT_SHARE and stacked + 2 * PADDING + margin <= room.x:
			return _layout(widths, row, margin, room, factor, true)
		if row + margin <= room.y * HEIGHT_SHARE and inline + 2 * PADDING + margin <= room.x:
			return _layout(widths, row, margin, room, factor, false)
	return _layout(widths, row, 0, container / 0.25, 0.25, true)


static func _layout(
	widths: Array[float], row: float, margin: float, room: Vector2, factor: float, stacked: bool
) -> Dictionary:
	var positions: Array[Vector2] = []
	var x := margin
	var y := room.y - margin - (widths.size() * row if stacked else row)
	for width in widths:
		positions.append(Vector2(x, y))
		if stacked:
			y += row
		else:
			x += width + 2 * PADDING + GAP
	return {"scale": factor, "positions": positions, "stacked": stacked, "row": row}


func render(state: Dictionary, container: Vector2) -> void:
	if not visible:
		return
	_lines = lines(state)
	var widths: Array[float] = []
	for line in _lines:
		widths.append(
			ceilf(_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
		)
	_plan = plan(container, widths, ceilf(_font.get_height(FONT_SIZE)))
	queue_redraw()


func _draw() -> void:
	if _plan.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * _plan.scale)
	for index in _lines.size():
		var at: Vector2 = _plan.positions[index]
		var width := (
			_font.get_string_size(_lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		)
		draw_rect(Rect2(at, Vector2(ceilf(width) + 2 * PADDING, _plan.row)), Color.BLACK)
		draw_string(
			_font,
			at + Vector2(PADDING, PADDING + _font.get_ascent(FONT_SIZE)),
			_lines[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			FONT_SIZE,
			Color.WHITE
		)
