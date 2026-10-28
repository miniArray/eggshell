extends Node2D
## Read-only run display. Pack visuals never supply simulation values.

const Pack = preload("res://src/level/asset_pack.gd")
const Frames = preload("res://src/view/pack_frames.gd")
const Life = preload("res://src/sim/life.gd")
const S := preload("res://src/sim/units.gd").SCALE
const FONT_SIZE := 16
const GAP := 8
var _frames := Frames.new()
var _state: Dictionary = {}
var _font: Font
var _bitmap := {}
var _sheet: Texture2D
var _icons: Array[Dictionary] = []
var _companion: Sprite2D
var _bubble: Sprite2D
var _rescuers: Array[Sprite2D] = []
var _world_root: Node2D
var _pack := ""
var _manifest: Dictionary = {}
var _items: Array[Dictionary] = []
var _plan := {}
var _dense := false


static func present(
	host: Node2D,
	world_root: Node2D,
	state: Dictionary,
	_world: Dictionary,
	manifest: Dictionary,
	pack: String
) -> void:
	var hud := host.get_node_or_null("RunHud")
	if hud == null:
		hud = load("res://src/view/hud.gd").new()
		hud.name = "RunHud"
		hud.z_index = 100
		hud.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		host.add_child(hud)
		hud.setup(manifest, pack)
	hud.render(state, host.get_viewport_rect().size, world_root)


func setup(manifest: Dictionary, pack: String) -> void:
	_manifest = manifest
	_dense = int(manifest.get("density", 1)) > 1
	_pack = pack
	_font = ThemeDB.fallback_font
	for key: String in ["hud", "MainFont", "ScoreFont", "LifeCounterFont"]:
		var entry: Variant = manifest.get("fonts", {}).get(key)
		if not entry is Dictionary or not Pack.safe_file(entry.get("file")):
			continue
		if bitmap_ok(entry):
			var sheet := _frames.texture(pack, entry.file)
			if (
				sheet != null
				and sheet.get_width() >= entry.cell_width
				and sheet.get_height() >= entry.cell_height
			):
				_bitmap = entry
				_sheet = sheet
				break
		elif str(entry.file).get_extension().to_lower() in ["ttf", "otf", "woff", "woff2"]:
			var file := FontFile.new()
			if file.load_dynamic_font(pack.path_join(entry.file)) == OK:
				_font = file
				break
	var hud_icons := _frames.visual(pack, manifest.get("hud", {}).get("HUDIcons", {}))
	var definitions := [
		manifest.get("hud", {}).get("countdown", manifest.get("hud", {}).get("LifeCounter", {})),
		manifest.get("hud", {}).get("coins", manifest.get("objects", {}).get("o1", {})),
		manifest.get("hud", {}).get("redcoins", {}),
		manifest.get("hud", {}).get("flowers", {})
	]
	for index in definitions.size():
		var art := _frames.visual(pack, definitions[index])
		if art.is_empty() and not hud_icons.is_empty() and index in [2, 3]:
			art = Frames.sample(hud_icons, 0, "", index - 1)
		_icons.append(art)


func render(state: Dictionary, container: Vector2, world_root: Node2D) -> void:
	_state = state
	if not is_instance_valid(_companion) or _world_root != world_root:
		_setup_companion(world_root)
	var mode := int(state.get("companion_mode", Life.ATTACHED))
	var anchor := (
		Vector2(
			state.get("recovery_x", state.x - state.facing * 10 * S),
			state.get("recovery_y", state.y - 24 * S)
		)
		/ S
	)
	_companion.position = anchor
	_companion.scale.x = (
		(int(state.facing) if mode == Life.ATTACHED else 1)
		/ float(int(_manifest.get("density", 1)) if _companion.has_meta("pack_art") else 1)
	)
	Frames.apply(_companion, int(state.frame), "cry" if mode == Life.BUBBLE else "idle")
	_bubble.position = anchor
	_bubble.visible = mode == Life.BUBBLE
	Frames.apply(_bubble, int(state.frame))
	for index in _rescuers.size():
		var node := _rescuers[index]
		node.visible = bool(state.get("rescue_active", 0)) and mode in [Life.BUBBLE, Life.TAKEN]
		node.position = (
			Vector2(
				state.get("rescue_%d_x" % (index + 1), 0), state.get("rescue_%d_y" % (index + 1), 0)
			)
			/ S
		)
		Frames.apply(node, int(state.frame))
	_items = readouts(state)
	var art_scale := maxi(1, roundi(world_root.scale.x / int(_manifest.get("density", 1))))
	var widths: Array[float] = []
	var heights: Array[float] = []
	for item: Dictionary in _items:
		var width := _measure(item.text)
		var height := _text_height()
		if item.icon >= 0 and not _icons[item.icon].is_empty():
			var size := _icon_size(_icons[item.icon])
			if _dense and width + size.x + GAP > container.x / art_scale:
				item.icon = -1  # Text takes priority over decorative art in a narrow window.
			else:
				width += size.x + GAP
				height = maxf(height, size.y)
		widths.append(width)
		heights.append(height)
	if _dense:
		_plan = dense_plan(container, widths, heights, art_scale)
	else:
		_plan = plan(container, widths, _text_height() + GAP)
	queue_redraw()


static func readouts(state: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = [
		{"text": "Stars %d" % int(state.get("health", 10)), "icon": 0},
		{"text": "Coins %d" % int(state.get("coins", 0)), "icon": 1},
		{
			"text":
			"Red %d/%d" % [int(state.get("redcoins", 0)), int(state.get("redcoins_target", 0))],
			"icon": 2
		},
		{
			"text":
			"Flowers %d/%d" % [int(state.get("flowers", 0)), int(state.get("flowers_target", 0))],
			"icon": 3
		}
	]
	var phase := int(state.get("life_phase", Life.PLAY))
	var status := ""
	match phase:
		Life.REJOIN:
			status = "Rescued"
		Life.DEAD, Life.FADE_OUT, Life.RESPAWN, Life.FADE_IN:
			status = "Respawn"
		Life.CHECKPOINT:
			status = "Checkpoint"
		Life.GOAL:
			status = "Goal" if state.get("life_ticks", 180) > 60 else "Score %d" % Life.score(state)
		Life.COMPLETE:
			status = "Complete  Score %d" % Life.score(state)
	if phase == Life.COMPLETE or (phase == Life.GOAL and state.get("life_ticks", 180) <= 60):
		items.append(
			{
				"text":
				"Hurt %d  Deaths %d" % [int(state.get("hits", 0)), int(state.get("deaths", 0))],
				"icon": -1
			}
		)
		items.append(
			{"text": "Time " + clock_text(int(state.get("total_play_ticks", 0))), "icon": -1}
		)
	if status.is_empty() and state.get("separated", 0):
		status = "Rescue"
	if not status.is_empty():
		items.append({"text": status, "icon": -1})
	return items


static func clock_text(ticks: int) -> String:
	var seconds := maxi(0, ticks) / 60
	var fraction := maxi(0, ticks) % 60 * 100 / 60
	return "%02d:%02d:%02d.%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60, fraction]


static func plan(container: Vector2, widths: Array[float], row_height: float = 24) -> Dictionary:
	if container.x <= 0 or container.y <= 0:
		return {}
	# Reflow first, then use integral or reciprocal-integral pixel scaling.
	var maximum := maxi(1, floori(minf(container.x / 832, container.y / 448)))
	var choices: Array[float] = []
	for factor in range(mini(maximum, 4), 0, -1):
		choices.append(float(factor))
	var widest := 0.0
	for width in widths:
		widest = maxf(widest, width)
	var limit := (
		ceili(
			maxf(
				(widest + 2 * GAP) / maxf(1, container.x),
				(widths.size() * row_height + 2 * GAP) / (container.y * 0.4)
			)
		)
		* 2
	)
	var divisor := 2
	while divisor <= maxi(2, limit):
		choices.append(1.0 / divisor)
		divisor *= 2
	var result := {"scale": 1.0, "positions": [], "size": Vector2.ZERO}
	for factor in choices:
		var available := maxf(1, container.x / factor)
		var margin := minf(GAP, available / 16)
		var positions: Array[Vector2] = []
		var x := margin
		var y := margin
		var right := margin
		var fits := true
		for width in widths:
			if x > margin and x + width + margin > available:
				x = margin
				y += row_height
			if width + 2 * margin > available:
				fits = false
			positions.append(Vector2(x, y))
			right = maxf(right, x + width + margin)
			x += width + GAP
		var height := y + row_height + margin
		result = {"scale": factor, "positions": positions, "size": Vector2(right, height) * factor}
		if fits and height * factor <= container.y * 0.4:
			return result
	return result


static func dense_plan(
	container: Vector2, widths: Array[float], heights: Array[float], art_scale: int
) -> Dictionary:
	# Keep the first (health/countdown) readout first. Wrap, never shrink art.
	var available := container.x / art_scale
	var margin := floorf(minf(GAP, available / 16))
	var at := Vector2(margin, margin)
	var row_height := 0.0
	var positions: Array[Vector2] = []
	for index in widths.size():
		if at.x > margin and at.x + widths[index] + margin > available:
			at.x = margin
			at.y += row_height + GAP
			row_height = 0
		positions.append(at)
		at.x += ceilf(widths[index]) + GAP
		row_height = maxf(row_height, ceilf(heights[index]))
	return {"scale": float(art_scale), "positions": positions}


func _icon_size(art: Dictionary) -> Vector2:
	if not _dense:
		return Vector2.ONE * _text_height()
	if art.has("animations"):
		return Frames.sample(art, int(_state.get("frame", 0))).texture.get_size()
	return art.texture.get_size()


func _draw() -> void:
	if _plan.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * _plan.scale)
	for index in _items.size():
		var item: Dictionary = _items[index]
		var at: Vector2 = _plan.positions[index]
		if item.icon >= 0 and not _icons[item.icon].is_empty():
			var art: Dictionary = _icons[item.icon]
			if art.has("animations"):
				art = Frames.sample(art, int(_state.frame))
			var size := _icon_size(art)
			draw_texture_rect(art.texture, Rect2(at, size), false)
			at.x += size.x + GAP
		_draw_text(item.text, at)


func _draw_text(text: String, at: Vector2) -> void:
	for character in text:
		var glyph := _glyph(character)
		if glyph >= 0:
			var cell := Vector2(_bitmap.cell_width, _bitmap.cell_height)
			var columns := maxi(1, int(_sheet.get_width() / cell.x))
			var source := Rect2(Vector2(glyph % columns, glyph / columns) * cell, cell)
			draw_texture_rect_region(_sheet, Rect2(at, cell), source)
		else:
			draw_string(
				_font,
				at + Vector2(0, _font.get_ascent(FONT_SIZE)),
				character,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				FONT_SIZE
			)
		at.x += _advance(character)


func _measure(text: String) -> float:
	var width := 0.0
	for character in text:
		width += _advance(character)
	return width


func _advance(character: String) -> float:
	if _glyph(character) >= 0:
		for pair: Array in _bitmap.get("widths", []):
			if character in pair[1]:
				return ceilf(float(pair[0])) if _dense else float(pair[0])
		return ceilf(float(_bitmap.cell_width)) if _dense else float(_bitmap.cell_width)
	var width := _font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return ceilf(width) if _dense else width


func _glyph(character: String) -> int:
	return str(_bitmap.characters).find(character) if _sheet != null else -1


func _text_height() -> float:
	return maxf(FONT_SIZE, float(_bitmap.get("cell_height", FONT_SIZE)))


static func bitmap_ok(entry: Dictionary) -> bool:
	if not Pack.safe_file(entry.get("file")) or not entry.get("characters") is String:
		return false
	if entry.characters.is_empty() or entry.characters.length() > 4096:
		return false
	for key: String in ["cell_width", "cell_height"]:
		if not Pack.number_ok(entry.get(key)) or entry[key] < 1 or entry[key] > 1024:
			return false
	if not entry.get("widths", []) is Array:
		return false
	for value: Variant in entry.get("widths", []):
		if (
			not value is Array
			or value.size() != 2
			or not Pack.number_ok(value[0])
			or value[0] < 0
			or value[0] > 4096
			or not value[1] is String
		):
			return false
	return true


func _setup_companion(world_root: Node2D) -> void:
	for node: Sprite2D in [_companion, _bubble] + _rescuers:
		if is_instance_valid(node):
			node.queue_free()
	_world_root = world_root
	var hud: Dictionary = _manifest.get("hud", {})
	var objects: Dictionary = _manifest.get("objects", {})
	_companion = _actor(
		hud.get("companion", objects.get("companion", {})),
		_plain_texture(16, 24),
		Vector2(8, 24),
		13
	)
	var bubble: Variant = hud.get("bubble", {})
	if not bubble is Dictionary:
		bubble = {}
	if (
		bubble.is_empty()
		and str(objects.get("recovery", {}).get("default_animation", "")).to_lower() == "bubble"
	):
		bubble = objects.recovery
	_bubble = _actor(bubble, _bubble_texture(), Vector2(32, 62), 12)
	_rescuers.clear()
	for index in 4:
		_rescuers.append(_actor(hud.get("captor", {}), _plain_texture(8, 12), Vector2(4, 6), 13))


func _actor(entry: Variant, fallback: Texture2D, anchor: Vector2, order: int) -> Sprite2D:
	var node := Sprite2D.new()
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.centered = false
	node.z_index = order
	var art := _frames.visual(_pack, entry, int(_manifest.get("density", 1)))
	if art.is_empty():
		node.texture = fallback
		node.offset = -anchor
	else:
		Frames.set_density(node, int(_manifest.get("density", 1)))
		node.set_meta("pack_art", art)
		Frames.apply(node, 0)
	node.set_meta("stateful", true)
	_world_root.add_child(node)
	return node


static func _plain_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


static func _bubble_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in 64:
		for x in 64:
			var distance := (x - 32) * (x - 32) + (y - 32) * (y - 32)
			if distance >= 28 * 28 and distance <= 30 * 30:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
