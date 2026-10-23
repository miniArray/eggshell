extends Node
## FileAccess.flush is a userspace flush, NOT an fsync durability guarantee.

const ITERATIONS: int = 200
const WARMUP: int = 10
const BYTES: int = 4096


func _ready() -> void:
	var directory: String = ""
	var fsync_tool: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--write-directory="):
			directory = argument.trim_prefix("--write-directory=")
		elif argument.begins_with("--write-fsync-tool="):
			fsync_tool = argument.trim_prefix("--write-fsync-tool=")
	if not directory.is_absolute_path():
		push_error("Pass --write-directory=/absolute/writable/path")
		get_tree().quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot make write directory")
		get_tree().quit(1)
		return
	var payload := PackedByteArray()
	payload.resize(BYTES)
	payload.fill(90)
	var samples := PackedFloat64Array()
	var temporary: String = directory.path_join("gdscript-save.new")
	var destination: String = directory.path_join("gdscript-save.bin")
	for index: int in range(ITERATIONS + WARMUP):
		var start: int = Time.get_ticks_usec()
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			push_error("Cannot open write probe: %s" % FileAccess.get_open_error())
			get_tree().quit(1)
			return
		file.store_buffer(payload)
		file.flush()
		var write_error: Error = file.get_error()
		file.close()
		# GNU `sync FILE` calls fsync(FILE); -f would sync the entire filesystem.
		if not fsync_tool.is_empty() and OS.execute(fsync_tool, [temporary]) != 0:
			push_error("fsync tool failed")
			get_tree().quit(1)
			return
		if write_error != OK or DirAccess.rename_absolute(temporary, destination) != OK:
			push_error("Write or rename failed")
			get_tree().quit(1)
			return
		var duration_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
		if index >= WARMUP:
			samples.append(duration_ms)
	get_tree().quit(_save_measurements(directory, fsync_tool, samples))


func _save_measurements(directory: String, fsync_tool: String, samples: PackedFloat64Array) -> int:
	var prefix: String = "gdscript-write" if fsync_tool.is_empty() else "gdscript-fsync"
	var raw := FileAccess.open(directory.path_join(prefix + ".csv"), FileAccess.WRITE)
	if raw == null:
		push_error("Cannot open write results")
		return 1
	raw.store_line("operation_ms")
	for sample: float in samples:
		raw.store_line(str(sample))
	raw.close()
	samples.sort()
	var result: Dictionary = {
		"operation":
		(
			"FileAccess open + write + flush + close + rename (NO fsync)"
			if fsync_tool.is_empty()
			else "FileAccess write + flush + close + GNU sync FILE (fsync) + rename; one process launch"
		),
		"directory_fsync": false,
		"bytes": BYTES,
		"iterations": ITERATIONS,
		"warmup_iterations": WARMUP,
		"p50_ms": samples[ceili(ITERATIONS * 0.50) - 1],
		"p99_ms": samples[ceili(ITERATIONS * 0.99) - 1],
	}
	var summary := FileAccess.open(directory.path_join(prefix + ".summary.json"), FileAccess.WRITE)
	if summary == null:
		push_error("Cannot open write summary")
		return 1
	summary.store_line(JSON.stringify(result, "\t"))
	summary.close()
	print("EGGSHELL_WRITE_SUMMARY " + JSON.stringify(result))
	return 0
