extends RefCounted
## Script constants of type modules, read once per script. Constants never change at run
## time, so a cached read answers exactly what get_script_constant_map() answers.
## Callers must not mutate a returned Array or Dictionary value.

static var _maps := {}


static func read(type: Script, key: String, fallback: Variant = null) -> Variant:
	var constants: Variant = _maps.get(type)
	if constants == null:
		constants = type.get_script_constant_map()
		_maps[type] = constants
	return constants.get(key, fallback)
