extends RefCounted
## Decorative parts of resizable spans, from their `E2` option: the stalk under the
## mushroom-style ledges (`E2` is its height in pixels) and the spike strip on the
## turning spans (`E2` picks strip 0 or 1). Drawing only: the parts have no collision,
## read no input and change no state.
##
## A pack supplies them as object entries named `<code>_stem` and `<code>_spikes`;
## a spikes entry may select its strip through `variants` keyed by `E2`, like other
## object entries. Without an entry a part draws as a diagnostic box of the same size.

const Frames = preload("res://src/view/pack_frames.gd")
const STEM_CODES := ["p6", "p7", "p8"]
const SPIKE_CODES := ["p11", "p12"]
const STEM_WIDTH := 32.0
## The stalk hangs from the ledge's bottom edge, half its 32 px height below its centre.
const STEM_TOP := 16.0
## The longest stalk drawn, in pixels; longer values are clamped.
const MAX_STEM := 100000
const SPIKE_HEIGHT := 10.0
## The strip stands on the span's top edge, 8 px above its centre, and turns with it.
const SPIKE_BOTTOM := -8.0
const SPIKE_MARGIN := 36.0
const SPIKE_FORMS := [0, 1]
static var _frames := Frames.new()
static var _boxes := {}


static func dressed(code: String) -> bool:
	return code in STEM_CODES or code in SPIKE_CODES


## The parts of one placement: {"name", "variant", "box", "stretch"} with `box` in
## world pixels relative to the placement, before its rotation. Pure.
static func parts(code: String, properties: Dictionary, span_width: float) -> Array:
	if not properties.has("E2"):
		return []
	var value := leading_integer(properties.E2)
	if code in STEM_CODES and value > 0:
		var height := float(mini(value, MAX_STEM))
		return [
			{
				"name": code + "_stem",
				"variant": 0,
				"box": Rect2(-STEM_WIDTH / 2, STEM_TOP, STEM_WIDTH, height),
				"stretch": "tile"
			}
		]
	if code in SPIKE_CODES and value in SPIKE_FORMS and span_width > 0:
		return [
			{
				"name": code + "_spikes",
				"variant": value,
				"box":
				Rect2(-span_width / 2, SPIKE_BOTTOM - SPIKE_HEIGHT, span_width, SPIKE_HEIGHT),
				"stretch": "patch"
			}
		]
	return []


## The whole-number prefix of a text or number option, as the original reads it;
## -1 when there is none or it is negative.
static func leading_integer(value: Variant) -> int:
	if value is int or value is float:
		return int(value) if is_finite(float(value)) and value >= 0 else -1
	if not value is String:
		return -1
	var text: String = value.strip_edges()
	var digits := ""
	for index in text.length():
		if not text[index].is_valid_int():
			break
		digits += text[index]
	return digits.to_int() if not digits.is_empty() and digits.length() <= 12 else -1


## Add the parts of a placement as children of its drawn node.
static func attach(
	node: Node2D,
	manifest: Dictionary,
	pack: String,
	code: String,
	properties: Dictionary,
	span_width: float
) -> void:
	for part: Dictionary in parts(code, properties, span_width):
		var art := _art(manifest, pack, part.name, part.variant)
		var child := (
			_diagnostic(part.name, part.box)
			if art.is_empty()
			else _drawn(art, part.box, part.stretch)
		)
		child.set_meta("span_part", part.box)
		child.z_as_relative = true
		node.add_child(child)
	follow(node)


## Keep the parts at world size while the span's node stretches to its width.
static func follow(node: Node2D) -> void:
	var scale := node.scale
	for child: Node in node.get_children():
		if not child is Node2D or not child.has_meta("span_part"):
			continue
		var part := child as Node2D
		var usable := absf(scale.x) > 0.0001 and absf(scale.y) > 0.0001
		part.visible = usable
		if not usable:
			continue
		var rect: Rect2 = child.get_meta("span_part")
		part.position = rect.position / scale
		part.scale = Vector2.ONE / scale


static func _art(manifest: Dictionary, pack: String, name: String, variant: int) -> Dictionary:
	var objects: Variant = manifest.get("objects", {})
	if not objects is Dictionary:
		return {}
	var entry: Variant = objects.get(name, {})
	if entry is Dictionary and entry.get("variants") is Dictionary:
		entry = entry.variants.get(str(variant), entry)
	if not entry is Dictionary or entry.is_empty():
		return {}
	return _frames.visual(pack, entry, int(manifest.get("density", 1)))


## Pack art fills the part's box: a stalk repeats down its height, a spike strip keeps
## its end caps and repeats its middle across the width.
static func _drawn(art: Dictionary, rect: Rect2, stretch: String) -> Node2D:
	var density := int(art.get("density", 1))
	var texture: Texture2D = art.texture
	var holder := Node2D.new()
	if stretch == "patch":
		var patch := NinePatchRect.new()
		patch.texture = texture
		patch.scale = Vector2.ONE / density
		var margin := mini(int(SPIKE_MARGIN) * density, texture.get_width() / 2)
		patch.patch_margin_left = margin
		patch.patch_margin_right = margin
		patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
		patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		patch.size = rect.size * density
		holder.add_child(patch)
	else:
		var image := Sprite2D.new()
		Frames.set_density(image, density)
		image.texture = texture
		image.centered = false
		image.region_enabled = true
		image.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		image.region_rect = Rect2(Vector2.ZERO, rect.size * density)
		holder.add_child(image)
	return holder


## The same stable per-name colour as the other diagnostic boxes.
static func _diagnostic(name: String, rect: Rect2) -> Node2D:
	if not _boxes.has(name):
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.from_hsv(float(absi(name.hash()) % 360) / 360.0, 0.55, 0.65))
		_boxes[name] = ImageTexture.create_from_image(image)
	var holder := Node2D.new()
	var box := Sprite2D.new()
	box.texture = _boxes[name]
	box.centered = false
	box.scale = rect.size
	holder.add_child(box)
	return holder
