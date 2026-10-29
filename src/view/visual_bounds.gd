extends RefCounted
## Conservative drawing envelopes, separate from collision geometry. Cached only for
## audited geometry-invariant looks. Unknown types and changing child layouts fail open.
const Policy = preload("res://src/view/view_visibility.gd")
const Registry = preload("res://src/sim/registry.gd")
const S := preload("res://src/sim/units.gd").SCALE
## These view_state implementations select frames, visibility, tint, mirrors or rotation,
## but never change size or position. New implementations must opt in after an audit.
const FIXED_LOOKS := [
	"actor",
	"armored_walker",
	"bare_runner",
	"bee_flyer",
	"blind_ghost",
	"bump_walker",
	"colour_block",
	"count_ledge",
	"dice_block",
	"disc_block",
	"drift_spore",
	"editor_blank",
	"egg_block",
	"element_shot",
	"enemy_overlap",
	"falling_span",
	"flat_walker",
	"gust_flyer",
	"hang_flyer",
	"hard_block",
	"helmet_walker",
	"hop_sprout",
	"item_egg",
	"item_star",
	"item_stem",
	"lamp",
	"lantern_walker",
	"launcher_shot",
	"lava_bubble",
	"mace_walker",
	"masked_shooter",
	"needle_juggler",
	"one_way_gate",
	"petal_stem",
	"pickup",
	"redirect_cloud",
	"ride_hound",
	"rise_balloon",
	"seed_melon",
	"seed_shot",
	"shell_walker",
	"shot_launcher",
	"shy_ghost",
	"slime_drop",
	"sneak_thief",
	"soft_walker",
	"spear_guard",
	"spike_hopper",
	"spike_pillar",
	"spike_sack",
	"spin_block",
	"spine_walker",
	"star_flower",
	"stem_petal",
	"thorn_block",
	"thorn_bush",
	"wing_drifter"
]


static func fixed_look(code: String) -> bool:
	var type := Registry.lookup(code)
	var name := type.resource_path.get_file().get_basename()
	return name in FIXED_LOOKS or (name == "item_block" and code in ["o9", "o15"])


static func placed(node: Sprite2D, code: String) -> Variant:
	# A snow tree emits independent saved puff positions; its crown is not their bound.
	if code == "d22" or node.get_meta("diagnostic_body", false):
		return null
	if node.get_meta("decor", false):
		return tree(node, false)
	if not fixed_look(code) or node.get_child_count() > 0:
		return null
	# Looks may turn or mirror around their origin. Cover every animation, not just
	# the first texture, including origins beyond the edge of an image.
	var rect: Variant = tree(node, false)
	return Policy.radial(rect) if rect is Rect2 else null


static func enemy(node: Sprite2D, code: String) -> Variant:
	if not fixed_look(code) or Registry.lookup(code).has_method("head_box"):
		return null
	var art: Dictionary = node.get_meta("entity_art", {})
	if art.is_empty():
		return null
	var density := int(art.get("density", 1))
	var rect: Variant = sprite_rect(node)
	if not rect is Rect2:
		return null
	var scale := Vector2.ONE / density
	if density > 1:
		scale = snapped_extent(scale, density)
	return Policy.radial(Transform2D(0, scale, 0, Vector2.ZERO) * (rect as Rect2)).grow(
		1.0 / density
	)


static func at_body(envelope: Variant, art: Dictionary, box: Array) -> Variant:
	if not envelope is Rect2 or art.get("anchor", "box") == "position":
		return envelope
	# Box-anchored art can move to either the centre or the bottom of the body.
	var reach := Vector2(maxi(absi(box[0]), absi(box[2])), maxi(absi(box[1]), absi(box[3]))) / S
	return (envelope as Rect2).grow(maxf(reach.x, reach.y))


## Union a static subtree in its parent's coordinates. Invisible children still
## count: visibility and frame selection may change before the next drawn frame.
static func tree(node: Node, include_position := true) -> Variant:
	var result: Variant = null
	if node is Sprite2D:
		result = sprite_rect(node)
	elif node is Control:
		result = Rect2(Vector2.ZERO, node.size)
	elif not node is Node2D:
		return null
	for child: Node in node.get_children():
		var part: Variant = tree(child)
		if part is Rect2:
			result = result.merge(part) if result is Rect2 else part
		else:
			return null
	if not result is Rect2:
		# Empty sprite parents are used for composed decorations.
		return Rect2() if node is Sprite2D and node.texture == null else null
	var transform: Transform2D = node.transform
	if not include_position:
		transform.origin = Vector2.ZERO
	var bounds: Rect2 = transform * (result as Rect2)
	if node is Sprite2D and node.has_meta("pack_density"):
		var density := int(node.get_meta("pack_density"))
		# Snap quantizes both scale axes, and then moves the corner by <= half a
		# screen pixel. ScreenPlan's world scale is always at least the density.
		var expanded := Transform2D(
			node.rotation, snapped_extent(node.scale, density), 0, transform.origin
		)
		bounds = bounds.merge(expanded * (result as Rect2)).grow(1.0 / density)
	return bounds


static func snapped_extent(scale: Vector2, density: int) -> Vector2:
	var result := scale
	for axis in 2:
		result[axis] = signf(scale[axis]) * maxf(1.0 / density, absf(scale[axis]) + 0.5 / density)
	return result


static func sprite_rect(node: Sprite2D) -> Variant:
	var art: Dictionary = node.get_meta("pack_art", {})
	if art.is_empty() or node.region_enabled:
		return node.get_rect() if node.texture != null else Rect2()
	var result: Variant = null
	for animation: Dictionary in art.animations.values():
		for frame: Dictionary in animation.frames:
			var rect := Rect2(-frame.origin, frame.texture.get_size())
			# Sprite flips reflect the rectangle about the origin, not its collision box.
			if node.flip_h:
				rect.position.x = -rect.end.x
			if node.flip_v:
				rect.position.y = -rect.end.y
			result = result.merge(rect) if result is Rect2 else rect
	return result
