extends RefCounted


static func read() -> Dictionary:
	var table: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://src/level/collision_table.json")
	)
	assert(table is Dictionary and table.get("version") == 2, "Unsupported collision table")
	# are private pack data and are applied by the view, never by the simulation.
	var index := 0
	for tile: Dictionary in table.tilemaps.values():
		tile["instances"] = [
			{"layer": "L2", "layer_index": 0, "z_order": index},
			{"layer": "L1", "layer_index": 1, "z_order": index}
		]
		index += 1
	return table
