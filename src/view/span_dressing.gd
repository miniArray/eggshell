extends RefCounted
## Decorative parts of resizable spans, from their `E2` option: the stalk under the
## mushroom-style ledges (`E2` is its height in pixels) and the spike strip on the
## turning spans (`E2` picks strip 0 or 1). Drawing only: the parts have no collision,
## read no input and change no state.
##
## A pack supplies them as object entries named `<code>_stem` and `<code>_spikes`;
## a spikes entry may select its strip through `variants` keyed by `E2`, like other
## object entries. Without an entry a part draws as a diagnostic box of the same size.
##
## The body of a resizable span (`p1`..`p21`) with pack art and `slices` is drawn in
## slices, not as one stretched image: `slices` gives the left, right, top and bottom
## margins in the pack image's pixels (kept at their size) and `fill` (`tile`, the
## default, or `stretch`) for the part between them. Without `slices` the fixed spans
## `p6`..`p21` (except the turning `p11`/`p12`) repeat their whole image; the others
## keep the stretched image the pack drew for them.

const Frames = preload("res://src/view/pack_frames.gd")
const Pack = preload("res://src/level/asset_pack.gd")
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
## Resizable spans whose body the source draws as a nine-slice panel. Their pack art is
## drawn in slices when its entry has `slices`; otherwise it keeps the stretched image,
## except for REPEAT_CODES, whose whole image repeats.
const BODY_CODES := [
	"p1",
	"p2",
	"p3",
	"p4",
	"p5",
	"p6",
	"p7",
	"p8",
	"p9",
	"p10",
	"p11",
	"p12",
	"p13",
	"p14",
	"p15",
	"p16",
	"p17",
	"p18",
	"p19",
	"p20",
	"p21"
]
const REPEAT_CODES := [
	"p6", "p7", "p8", "p9", "p10", "p13", "p14", "p15", "p16", "p17", "p18", "p19", "p20", "p21"
]
## The largest slice margin read from a pack, in image pixels.
const MAX_SLICE := 4096
static var _frames := Frames.new()
static var _boxes := {}


static func dressed(code: String) -> bool:
	return code in STEM_CODES or code in SPIKE_CODES or code in BODY_CODES


## Whether a pack entry names its slices.
static func has_slices(entry: Variant) -> bool:
	return entry is Dictionary and entry.get("slices") is Dictionary


## The slices of a span body entry: {"left", "right", "top", "bottom"} margins in image
## pixels and "tile" (false when the middle stretches). Invalid values read as 0. Pure.
static func slices(entry: Variant) -> Dictionary:
	var result := {"left": 0, "right": 0, "top": 0, "bottom": 0, "tile": true}
	if not entry is Dictionary or not entry.get("slices") is Dictionary:
		return result
	var given: Dictionary = entry.slices
	for key: String in ["left", "right", "top", "bottom"]:
		var value: Variant = given.get(key, 0)
		if Pack.number_ok(value) and value >= 0 and value <= MAX_SLICE:
			result[key] = int(value)
	result.tile = str(given.get("fill", "tile")) != "stretch"
	return result


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
	var variant := int(properties.get("F", 0))
	var entry: Variant = _entry(manifest, code, variant)
	if node is Sprite2D and code in BODY_CODES and (has_slices(entry) or code in REPEAT_CODES):
		attach_body(node, _art(manifest, pack, code, variant), entry)
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


## Draw a resizable span's pack art in slices over the node's own stretched image, which
## is hidden. `node` is the span's uncentred sprite; `follow` sizes the slices to the area
## that image covers, so they track the node's stretch, mirror and turn. `entry` is the
## pack's object entry (its `slices`). Without art nothing changes.
static func attach_body(node: Sprite2D, art: Dictionary, entry: Variant) -> void:
	if art.is_empty() or node.texture == null:
		return
	var cuts := slices(entry)
	var density := int(art.get("density", 1))
	var holder := _sliced(art, Rect2(), cuts)
	holder.set_meta("span_body", density)
	holder.z_as_relative = true
	node.add_child(holder)
	node.move_child(holder, 0)
	node.self_modulate.a = 0.0
	follow(node)


## Keep the parts at world size while the span's node stretches to its width.
static func follow(node: Node2D) -> void:
	var scale := node.scale
	var usable := absf(scale.x) > 0.0001 and absf(scale.y) > 0.0001
	for child: Node in node.get_children():
		if not child is Node2D:
			continue
		var part := child as Node2D
		if part.has_meta("span_body"):
			part.visible = usable
			if usable:
				_lay_body(node as Sprite2D, part)
			continue
		if not part.has_meta("span_part"):
			continue
		part.visible = usable
		if not usable:
			continue
		var rect: Rect2 = child.get_meta("span_part")
		part.position = rect.position / scale
		part.scale = Vector2.ONE / scale


## Fit a body's slices to the area the node's stretched image covers.
static func _lay_body(node: Sprite2D, holder: Node2D) -> void:
	var size: Vector2 = node.texture.get_size() if node.texture != null else Vector2.ZERO
	var scale := node.scale
	var corner := node.offset
	# A mirrored axis draws the holder back from the far edge of the image area.
	for axis in 2:
		if scale[axis] < 0:
			corner[axis] += size[axis]
	holder.position = corner
	holder.scale = Vector2.ONE / scale
	var patch := holder.get_child(0) as NinePatchRect
	patch.size = (size * scale).abs() * int(holder.get_meta("span_body"))


static func _art(manifest: Dictionary, pack: String, name: String, variant: int) -> Dictionary:
	var entry: Variant = _entry(manifest, name, variant)
	if not entry is Dictionary or entry.is_empty():
		return {}
	return _frames.visual(pack, entry, int(manifest.get("density", 1)))


## The pack's object entry for a name and placed variant, or {}.
static func _entry(manifest: Dictionary, name: String, variant: int) -> Variant:
	var objects: Variant = manifest.get("objects", {})
	if not objects is Dictionary:
		return {}
	var entry: Variant = objects.get(name, {})
	if entry is Dictionary and entry.get("variants") is Dictionary:
		entry = entry.variants.get(str(variant), entry)
	return entry


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


## Pack art in slices: margins keep their size, the middle tiles or stretches to the box.
static func _sliced(art: Dictionary, rect: Rect2, cuts: Dictionary) -> Node2D:
	var density := int(art.get("density", 1))
	var texture: Texture2D = art.texture
	var holder := Node2D.new()
	var patch := NinePatchRect.new()
	patch.texture = texture
	patch.scale = Vector2.ONE / density
	patch.patch_margin_left = mini(cuts.left, texture.get_width())
	patch.patch_margin_right = mini(cuts.right, texture.get_width())
	patch.patch_margin_top = mini(cuts.top, texture.get_height())
	patch.patch_margin_bottom = mini(cuts.bottom, texture.get_height())
	var mode := (
		NinePatchRect.AXIS_STRETCH_MODE_TILE
		if cuts.tile
		else NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	patch.axis_stretch_horizontal = mode
	patch.axis_stretch_vertical = mode
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	patch.size = rect.size * density
	holder.add_child(patch)
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
