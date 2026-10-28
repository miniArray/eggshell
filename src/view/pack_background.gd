extends Node2D
## Background fields come from the selected map, not from mutable play state.
const Pack = preload("res://src/level/asset_pack.gd")
const Frames = preload("res://src/view/pack_frames.gd")
var _images := Frames.new()
var _layers: Array[Dictionary] = []
var _strips: Array[Dictionary] = []
var _plan: Dictionary = {}
var _gradient_scroll := Vector2.ZERO
var _reference := Vector2.ZERO
var _tick := 0
var _density := 1
var _binary_alpha := {}


func setup(manifest: Dictionary, pack: String, map: Dictionary) -> void:
	z_index = -30
	_density = int(manifest.get("density", 1))
	var backgrounds: Dictionary = manifest.get("backgrounds", {})
	var previous := {}
	for slot: String in ["bg1", "bg2", "bg3"]:
		var preceding := previous
		var layers: Array[Dictionary] = []
		var choice := str(map.get(slot, "0")).split(",")
		var entry: Variant = backgrounds.get(choice[0], {})
		if not entry is Dictionary:
			continue
		var variant := int(choice[1]) if choice.size() > 1 else 0
		if entry.get("variants") is Dictionary and entry.variants.get(str(variant)) is Dictionary:
			entry = entry.duplicate()
			entry.merge(entry.variants[str(variant)], true)
		if not entry.get("layers", []) is Array:
			continue
		for layer: Variant in entry.get("layers", []):
			if not layer is Dictionary:
				continue
			var file: Variant = layer.get("file")
			var frame_origin: Variant = [0, 0]
			var frames: Variant = layer.get("frames", [])
			if frames is Array and not frames.is_empty():
				var index := clampi(
					int(choice[1]) if choice.size() > 1 else 0, 0, frames.size() - 1
				)
				var frame: Variant = frames[index]
				file = frame.get("file") if frame is Dictionary else frame
				if frame is Dictionary:
					frame_origin = frame.get("origin", [0, 0])
			var art := {}
			var selected_frame := int(layer.get("frame", 0))
			var texture: Texture2D
			if Pack.animation_ok(layer.get("animation")):
				art = _images.visual(pack, {"animations": {"default": layer.animation}})
				if not art.is_empty():
					var frame := Frames.sample(art, 0, "", selected_frame)
					texture = frame.texture
					frame_origin = [frame.origin.x, frame.origin.y]
			else:
				texture = _images.texture(pack, file)
			if texture == null:
				continue
			var scroll: Variant = layer.get("scroll", [1, 1])
			var slots: Variant = entry.get("slots", {})
			var slot_offset := Vector2.ZERO
			if slots is Dictionary and slots.get(slot) is Dictionary:
				scroll = slots[slot].get("scroll", scroll)
				var offsets: Variant = slots[slot].get("offset_by_height", {})
				if offsets is Dictionary:
					var extra: Variant = offsets.get(str(int(map.get("height", 0))), [0, 0])
					if Pack.point_ok(extra):
						slot_offset = Vector2(extra[0], extra[1])
			var scale: Variant = layer.get("scale", [1, 1])
			var offset: Variant = layer.get("offset", [0, 0])
			var reference: Variant = layer.get("reference", [0, 0])
			if not Pack.point_ok(scroll) or not Pack.point_ok(scale) or not Pack.point_ok(offset):
				continue
			if not Pack.point_ok(reference) or scale[0] <= 0 or scale[1] <= 0:
				continue
			if layer.has("anchor"):
				if not Pack.point_ok(layer.anchor) or not Pack.point_ok(frame_origin):
					continue
				offset = [
					layer.anchor[0] - frame_origin[0] * scale[0],
					layer.anchor[1] - frame_origin[1] * scale[1]
				]
			var period: Variant = layer.get("repeat_size", [0, 0])
			if not Pack.point_ok(period):
				continue
			(
				layers
				. append(
					{
						"texture": texture,
						"scroll": Vector2(scroll[0], scroll[1]),
						"scale": Vector2(scale[0], scale[1]) / _density,
						"offset": (Vector2(offset[0], offset[1]) + slot_offset) / _density,
						"anchor":
						(
							(Vector2(layer.anchor[0], layer.anchor[1]) + slot_offset) / _density
							if layer.has("anchor")
							else Vector2.ZERO
						),
						"origin":
						(
							Vector2(frame_origin[0], frame_origin[1])
							if Pack.point_ok(frame_origin)
							else Vector2.ZERO
						),
						"art": art,
						"frame": selected_frame,
						"anchored": layer.has("anchor"),
						"period": Vector2(period[0], period[1]) / _density,
						"min_repeat": int(layer.get("min_repeat", -4096)),
						"reference": Vector2(reference[0], reference[1]) / _density,
						"repeat_x": bool(layer.get("repeat_x", true)),
						"repeat_y": bool(layer.get("repeat_y", false)),
					}
				)
			)
		if layers.is_empty():
			continue
		previous = {"id": choice[0], "variant": variant, "layers": layers}
		# Only consecutive identical drawn groups are idempotent. Intervening art
		# changes painter order; partial alpha accumulates even for identical groups.
		if previous != preceding or not _binary_layers(layers):
			_layers.append_array(layers)
	var parts := str(map.get("gradient", "")).split("_")
	var gradients: Dictionary = manifest.get("gradients", {})
	var gradient: Variant = gradients.get(parts[0], {})
	var pack_gradient: bool = gradient is Dictionary and not gradient.is_empty()
	# Custom strips use height,r,g,b groups, with the same map offset and scale fields.
	if not gradient is Dictionary or gradient.is_empty():
		gradient = {"strips": decode_strips(parts[0])}
	var strips: Variant = gradient.get("strips", [])
	if not strips is Array:
		return
	var scroll: Variant = gradient.get("scroll", [0, 0])
	var reference: Variant = gradient.get("reference", [0, 0])
	if Pack.point_ok(scroll):
		_gradient_scroll = Vector2(scroll[0], scroll[1])
	if Pack.point_ok(reference):
		_reference = Vector2(reference[0], reference[1]) / _density
	var scale := float(parts[2]) if parts.size() > 2 and parts[2].is_valid_float() else 1.0
	var offset := float(parts[1]) if parts.size() > 1 and parts[1].is_valid_float() else 0.0
	if not is_finite(scale) or scale <= 0 or not is_finite(offset):
		return
	var y := 0.0
	for index in strips.size():
		var strip: Variant = strips[index]
		if not strip is Dictionary or not Pack.number_ok(strip.get("height")):
			continue
		var rgb: Variant = strip.get("color")
		if not rgb is Array or rgb.size() != 3:
			continue
		if not Pack.number_ok(rgb[0]) or not Pack.number_ok(rgb[1]) or not Pack.number_ok(rgb[2]):
			continue
		var strip_height := float(strip.height) / (_density if pack_gradient else 1)
		var height := maxf(0, offset if index == 0 else strip_height) * scale
		_strips.append(
			{
				"y": y,
				"height": height,
				"color": Color(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)
			}
		)
		y += height


func _binary_layers(layers: Array[Dictionary]) -> bool:
	for layer: Dictionary in layers:
		if not _binary_texture(layer.texture):
			return false
		for animation: Dictionary in layer.art.get("animations", {}).values():
			for frame: Dictionary in animation.frames:
				if not _binary_texture(frame.texture):
					return false
	return true


func _binary_texture(texture: Texture2D) -> bool:
	var key := texture.get_instance_id()
	if not _binary_alpha.has(key):
		_binary_alpha[key] = _binary_image(texture.get_image())
	return _binary_alpha[key]


static func _binary_image(image: Image) -> bool:
	if image == null:
		return false
	if image.is_compressed() and image.decompress() != OK:
		return false
	# Only byte formats can be converted without rounding fractional alpha away.
	if not (
		image.get_format()
		in [
			Image.FORMAT_L8,
			Image.FORMAT_LA8,
			Image.FORMAT_R8,
			Image.FORMAT_RG8,
			Image.FORMAT_RGB8,
			Image.FORMAT_RGBA8
		]
	):
		return false
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	# detect_alpha() treats alpha 1 as transparent and 254 as opaque. Neither
	# is idempotent, so inspect the exact stored alpha instead of that hint.
	for index in range(3, pixels.size(), 4):
		if pixels[index] != 0 and pixels[index] != 255:
			return false
	return true


static func decode_strips(value: String) -> Array:
	var tokens := value.split(",")
	var strips := []
	if tokens.size() % 4 != 0:
		return strips
	for start in range(0, tokens.size(), 4):
		for index in range(start, start + 4):
			if not tokens[index].is_valid_float() or not is_finite(float(tokens[index])):
				return []
		strips.append(
			{
				"height": float(tokens[start]),
				"color":
				[float(tokens[start + 1]), float(tokens[start + 2]), float(tokens[start + 3])]
			}
		)
	return strips


func render(plan: Dictionary, tick: int) -> void:
	_plan = plan
	_tick = tick
	queue_redraw()


func _draw() -> void:
	if _plan.is_empty():
		return
	var visible := Rect2(_plan.center - _plan.visible / 2.0, _plan.visible)
	var shift: Vector2 = (_plan.center - _reference) * (Vector2.ONE - _gradient_scroll)
	for strip: Dictionary in _strips:
		draw_rect(
			Rect2(visible.position.x, strip.y + shift.y, visible.size.x, strip.height), strip.color
		)
	for layer: Dictionary in _layers:
		draw_layer(layer, visible)


func draw_layer(layer: Dictionary, visible: Rect2) -> void:
	var texture: Texture2D = layer.texture
	var scale: Vector2 = layer.scale
	if _density > 1:
		scale = (
			Vector2(maxf(1, roundf(scale.x * _plan.scale)), maxf(1, roundf(scale.y * _plan.scale)))
			/ _plan.scale
		)
	var offset: Vector2 = layer.offset
	if _density > 1 and layer.anchored:
		offset = layer.anchor - layer.origin * scale
	if not layer.art.is_empty():
		var frame := Frames.sample(layer.art, _tick, "", layer.frame)
		texture = frame.texture
		if layer.anchored:
			offset = layer.anchor - frame.origin * scale
	var size: Vector2 = Vector2(texture.get_size()) * scale
	var origin: Vector2 = offset + (_plan.center - layer.reference) * (Vector2.ONE - layer.scroll)
	if _density > 1:
		origin = (
			((origin * _plan.scale + _plan.offset.round()).round() - _plan.offset.round())
			/ _plan.scale
		)
	var period := Vector2(
		layer.period.x if layer.period.x > 0 else size.x,
		layer.period.y if layer.period.y > 0 else size.y
	)
	if _density > 1:
		period = (period * _plan.scale).round().max(Vector2.ONE) / _plan.scale
	if period != size:
		var first_x := (
			maxi(layer.min_repeat, floori((visible.position.x - origin.x - size.x) / period.x))
			if layer.repeat_x
			else 0
		)
		var last_x := ceili((visible.end.x - origin.x) / period.x) if layer.repeat_x else 0
		var first_y := (
			floori((visible.position.y - origin.y - size.y) / period.y) if layer.repeat_y else 0
		)
		var last_y := ceili((visible.end.y - origin.y) / period.y) if layer.repeat_y else 0
		for y in range(first_y, mini(last_y + 1, first_y + 4096)):
			for x in range(first_x, mini(last_x + 1, first_x + 4096)):
				draw_texture_rect(texture, Rect2(origin + Vector2(x, y) * period, size), false)
		return
	var first := origin
	var end := origin + size
	if layer.repeat_x:
		first.x += floorf((visible.position.x - origin.x) / size.x) * size.x
		end.x = visible.end.x + size.x
	if layer.repeat_y:
		first.y += floorf((visible.position.y - origin.y) / size.y) * size.y
		end.y = visible.end.y + size.y
	# Tile in one draw call. Neither map width nor tiny scales allocate more nodes.
	draw_set_transform(Vector2.ZERO, 0, scale)
	draw_texture_rect(texture, Rect2(first / scale, (end - first) / scale), true)
	draw_set_transform(Vector2.ZERO)
