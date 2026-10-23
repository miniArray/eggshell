extends Node
## Opt-in wall-clock frame intervals. Rendering/GPU time is not measured separately.

var _file: FileAccess
var _path: String = ""
var _samples := PackedFloat64Array()
var _previous_usec: int = 0
var _start_usec: int = 0
var _warmup_usec: int = 2_000_000
var _finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_path = OS.get_environment("EGGSHELL_FRAME_LOG")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frame-log="):
			_path = argument.trim_prefix("--frame-log=")
		elif argument.begins_with("--frame-warmup="):
			_warmup_usec = int(
				maxf(0.0, argument.trim_prefix("--frame-warmup=").to_float()) * 1_000_000
			)
	if _path.is_empty():
		set_process(false)
		return
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("Cannot open frame log: %s (%s)" % [_path, FileAccess.get_open_error()])
		get_tree().quit(1)
		return
	_file.store_line("elapsed_ms,frame_ms")
	_start_usec = Time.get_ticks_usec()
	_previous_usec = _start_usec


func _process(_delta: float) -> void:
	if _file == null:
		return
	var now: int = Time.get_ticks_usec()
	var elapsed: int = now - _start_usec
	var frame_ms: float = float(now - _previous_usec) / 1000.0
	_previous_usec = now
	# Use ticks, not delta: Godot can clamp or smooth delta during a long stall.
	if elapsed < _warmup_usec:
		return
	_samples.append(frame_ms)
	_file.store_line("%.3f,%.3f" % [float(elapsed) / 1000.0, frame_ms])


func finish() -> void:
	if _file == null or _finished:
		return
	_finished = true
	_file.close()
	var sorted: PackedFloat64Array = _samples.duplicate()
	sorted.sort()
	var total_ms: float = 0.0
	for sample: float in _samples:
		total_ms += sample
	var rss_kib: int = _peak_rss_kib()
	var result: Dictionary = {
		"frames": sorted.size(),
		"warmup_ms": float(_warmup_usec) / 1000.0,
		"p50_ms": _percentile(sorted, 0.50),
		"p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99),
		"mean_fps": 1000.0 * float(sorted.size()) / total_ms if total_ms > 0.0 else 0.0,
		"peak_rss_kib": rss_kib,
		"peak_rss_source": "/proc/self/status VmHWM" if rss_kib >= 0 else "unavailable",
		"godot": Engine.get_version_info()["string"],
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"display_server": DisplayServer.get_name(),
		"viewport": str(get_viewport().get_visible_rect().size),
	}
	var summary := FileAccess.open(_path + ".summary.json", FileAccess.WRITE)
	if summary == null:
		push_error("Cannot open frame summary: " + _path)
		return
	summary.store_line(JSON.stringify(result, "\t"))
	summary.close()
	print("EGGSHELL_FRAME_SUMMARY " + JSON.stringify(result))


func _exit_tree() -> void:
	finish()


static func _percentile(sorted: PackedFloat64Array, percentile: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[maxi(0, ceili(percentile * sorted.size()) - 1)]


static func _peak_rss_kib() -> int:
	var status := FileAccess.open("/proc/self/status", FileAccess.READ)
	if status == null:
		return -1
	# procfs reports a zero file length; read lines rather than get_as_text().
	while not status.eof_reached():
		var line: String = status.get_line()
		if line.begins_with("VmHWM:"):
			return line.trim_prefix("VmHWM:").strip_edges().split(" ", false)[0].to_int()
	return -1
