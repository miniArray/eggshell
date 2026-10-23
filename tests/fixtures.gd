extends RefCounted
## Original geometric courses used by the public test suite.

const World = preload("res://src/sim/world.gd")
const Collision = preload("res://src/level/collision_table.gd")


static func code(name: String = "actors") -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/%s.level.json" % name)


static func world(name: String = "actors") -> Dictionary:
	var result := World.build(code(name), Collision.read())
	assert(result.ok, str(result))
	return result.world


static func recording(name: String) -> Array:
	return JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/%s.input.json" % name)
	)
