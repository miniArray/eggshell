extends SceneTree
## Dispatch caches and area queries on invented entities. No levels, scenes or assets.

const Registry = preload("res://src/sim/registry.gd")
const S := preload("res://src/sim/units.gd").SCALE
var checks := 0
var failures := 0


func _initialize() -> void:
	cache_checks()
	nearby_checks()
	print("NEARBY_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## The caches answer what a scan of TYPES and the script constants answers.
func cache_checks() -> void:
	for code: String in Registry.codes() + ["neutral_unknown", "?e1", ""]:
		var expected: Script = Registry.Inert
		for type: Script in Registry.TYPES:
			if code in type.CODES:
				expected = type
				break
		check(Registry.lookup(code) == expected, "Lookup matches the type scan: " + code)
		var type := Registry.lookup(code)
		var constants := type.get_script_constant_map()
		for key: String in [
			"SOLID", "ENEMY", "STEP_PHASE", "CONTACT_PHASE", "DYNAMIC", "GOAL_COIN"
		]:
			check(
				Registry.constant(type, key, -7) == constants.get(key, -7),
				"Constant matches the script: %s %s" % [code, key]
			)
		var fresh := Registry.COMMON_FIELDS.duplicate(true)
		fresh.append_array(type.FIELDS.duplicate(true))
		check(Registry.fields(code) == fresh, "Schema matches a fresh composition: " + code)
	var copy := Registry.fields("o28")
	copy[0][1] = 99
	check(Registry.fields("o28")[0][1] == 0, "Callers receive a private schema copy")


func nearby_checks() -> void:
	var state := {"entities": []}
	var seed := 12345
	var codes := ["o28", "neutral_unknown", "o28", "o12"]
	for index in 400:
		seed = (seed * 1103515245 + 12345) % 2147483648
		var x := (seed % 4000) * S
		seed = (seed * 1103515245 + 12345) % 2147483648
		var y := (seed % 1000) * S
		state.entities.append(
			{"code": codes[index % codes.size()], "id": str(index), "x": x, "y": y, "status": 1}
		)
	var probes := [
		[0, 0, 64 * S, 64 * S],
		[1000 * S, 200 * S, 1400 * S, 260 * S],
		[-500 * S, -500 * S, -400 * S, -400 * S],
		[0, 0, 4000 * S, 1000 * S]
	]
	# Touching edges count: a hard block whose right edge meets the probe's left edge.
	state.entities.append({"code": "o28", "id": "edge", "x": 1968 * S, "y": 500 * S, "status": 3})
	probes.append([2000 * S, 500 * S, 2010 * S, 510 * S])
	for probe: Array in probes:
		var expected := []
		for entity: Dictionary in state.entities:
			var type := Registry.lookup(entity.code)
			var b: Array = type.bounds(entity) if type.has_method("bounds") else [0, 0, 0, 0]
			if (
				entity.x + b[2] >= probe[0]
				and entity.x + b[0] <= probe[2]
				and entity.y + b[3] >= probe[1]
				and entity.y + b[1] <= probe[3]
			):
				expected.append(entity)
		var found := Registry.nearby(state, {}, probe)
		check(found.size() == expected.size(), "Nearby finds every candidate: %s" % [probe])
		var ordered := true
		for index in mini(found.size(), expected.size()):
			ordered = ordered and is_same(found[index], expected[index])
		check(ordered, "Nearby keeps entity order: %s" % [probe])
	var edge := Registry.nearby(state, {}, probes[-1])
	check(edge.any(func(e: Dictionary) -> bool: return e.id == "edge"), "Touching edge included")
	check(Registry.nearby({"entities": []}, {}, probes[0]).is_empty(), "Empty table")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
