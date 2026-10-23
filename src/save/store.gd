class_name SaveStore
extends RefCounted
## One persistent I/O worker. Only immutable snapshot bytes cross the boundary.
## flush + same-directory rename: process-kill safe, NOT power-loss durable.

var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending := {}
var _results := []
var _closing := false


func start() -> Error:
	return _thread.start(_work)


func submit(path: String, bytes: PackedByteArray, frame: int) -> void:
	_mutex.lock()
	_pending[path] = {"bytes": bytes, "frame": frame}
	_mutex.unlock()
	_wake.post()


func results() -> Array:
	_mutex.lock()
	var completed := _results
	_results = []
	_mutex.unlock()
	return completed


func close() -> void:
	if not _thread.is_started():
		return
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()


func _work() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var batch := _pending
		_pending = {}
		var closing := _closing
		_mutex.unlock()
		for path: String in batch:
			var began := Time.get_ticks_usec()
			var error := _write(path, batch[path].bytes)
			var result := {
				"path": path,
				"frame": batch[path].frame,
				"error": error,
				"write_ms": (Time.get_ticks_usec() - began) / 1000.0
			}
			_mutex.lock()
			_results.append(result)
			_mutex.unlock()
		if closing:
			break


static func _write(path: String, bytes: PackedByteArray) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path + ".new", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".new", path)
