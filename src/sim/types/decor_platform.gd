extends RefCounted
## Static scenery ledges. Separate strips must not fill the gaps between them.

const Decor = preload("res://src/sim/types/decor.gd")
const S := preload("res://src/sim/units.gd").SCALE
const CODES := ["d5", "d6", "d7", "d8", "d23"]
const FIELDS := [["decor_variant", 0], ["decor_mirror", 0]]
const STEP_PHASE := -1
const SOLID := 2


static func prepare(source: Dictionary, _world: Dictionary) -> Dictionary:
	var result := Decor.prepare_options(source)
	if result.ok and source.decor.rotation != 0:
		return {"ok": false, "degrade": true, "error": "rotated scenery ledge"}
	return result


static func create(source: Dictionary, _world: Dictionary) -> Dictionary:
	return {"decor_variant": int(source.variant), "decor_mirror": int(source.mirror)}


static func step(_entity: Dictionary, _state: Dictionary, _world: Dictionary) -> void:
	pass


static func solid_boxes(entity: Dictionary) -> Array:
	var strips: Array
	match entity.code:
		"d5":
			strips = [[-42, -32, 38, -30]]
		"d6":
			strips = [[-27, -18, 23, -16]]
		"d7":
			strips = [[-26, -48, 54, -46], [-55, 14, -5, 16]]
		"d8":
			strips = [[-38, -80, 42, -78], [21, -18, 71, -16], [-70, 16, 10, 18]]
		"d23":
			strips = [[-32, -16, 28, -14]] if entity.decor_variant == 0 else [[-60, -48, 56, -46]]
		_:
			return []
	var result := []
	for strip: Array in strips:
		var left: int = -strip[2] if entity.decor_mirror else strip[0]
		var right: int = -strip[0] if entity.decor_mirror else strip[2]
		result.append(
			[
				entity.x + left * S,
				entity.y + strip[1] * S,
				entity.x + right * S,
				entity.y + strip[3] * S
			]
		)
	return result


static func valid(entity: Dictionary) -> bool:
	return (
		entity.code in CODES
		and entity.decor_variant >= 0
		and entity.decor_variant < Decor.frame_count(entity.code)
		and entity.decor_mirror in [0, 1]
		and (entity.code != "d23" or entity.decor_mirror == 0)
	)
