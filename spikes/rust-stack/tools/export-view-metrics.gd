extends SceneTree
## Offline reference metadata only. Candidate never calls Godot.


func _initialize() -> void:
	var font := ThemeDB.fallback_font
	var metrics := {
		"godot": Engine.get_version_info().string,
		"font_size": 16,
		"space_advance": font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x,
		"font_height": font.get_height(16),
		"font_ascent": font.get_ascent(16),
	}
	var text := JSON.stringify(metrics)
	print("RUST_VIEW_METRICS ", text)
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		DirAccess.make_dir_recursive_absolute(arguments[0].get_base_dir())
		var file := FileAccess.open(arguments[0], FileAccess.WRITE)
		if file == null:
			quit(2)
			return
		file.store_string(text)
	quit()
