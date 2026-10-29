extends SceneTree
## The real game composition: while the play state is invalid, autosave writes nothing
## and keeps trying every step; it resumes on the first step the state is valid again,
## without waiting for the next 60-step mark. Placeholder graphics, no audio, an
## original test course and a temporary save folder.
const Game = preload("res://src/view/game.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
var _checks := 0
var _failures := 0
var _game: Node
var _base := "/tmp/eggshell-autosave-retry-%d" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	check(
		Game.autosave_due(120, false) and not Game.autosave_due(121, false),
		"Autosave is due every 60 steps"
	)
	check(Game.autosave_due(121, true), "After a refusal autosave is due every step")
	_game = Game.new()
	_game.launch_options = {
		"level-code": "res://tests/fixtures/stride.level.json",
		"save-dir": _base,
		"placeholder": "true",
		"mute": "true",
		"smooth": "off"
	}
	root.add_child(_game)
	await until(func() -> bool: return saved_frame() > 0, 240)
	check(saved_frame() > 0, "Autosave writes while the state is valid")
	# An out-of-range saved counter that play never writes makes the state invalid.
	var deaths: int = _game.state.deaths
	_game.state.deaths = -5
	var refused_at: int = _game.state.frame
	# A write already handed to the save worker may still land; let it.
	await until(func() -> bool: return _game.state.frame > refused_at + 5, 30)
	var before := saved_frame()
	await until(func() -> bool: return _game.state.frame > refused_at + 75, 300)
	check(saved_frame() == before, "Nothing is written while the state is invalid")
	await until(func() -> bool: return _game.state.frame % 60 == 20, 120)
	_game.state.deaths = deaths
	var valid_at: int = _game.state.frame
	await until(func() -> bool: return saved_frame() > before, 120)
	var resumed := saved_frame()
	check(
		resumed > valid_at and resumed < valid_at + 30,
		"Autosave resumes on the next step once valid (valid at %d, saved %d)" % [valid_at, resumed]
	)
	var next := resumed - resumed % 60 + 60
	await until(func() -> bool: return saved_frame() >= next, 150)
	check(saved_frame() % 60 == 0, "Then it returns to every 60 steps (saved %d)" % saved_frame())
	_game.queue_free()
	await process_frame
	DirAccess.remove_absolute(_base.path_join("autosave.egg"))
	DirAccess.remove_absolute(_base.path_join("settings.json"))
	DirAccess.remove_absolute(_base)
	print("AUTOSAVE_RETRY_RESULT: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## The frame stored in the autosave file, or 0 without one.
func saved_frame() -> int:
	var path := _base.path_join("autosave.egg")
	if not FileAccess.file_exists(path):
		return 0
	var bytes := FileAccess.get_file_as_bytes(path)
	var decoded := Snapshot.decode(bytes, _game.world.identity)
	return int(decoded.state.frame) if decoded.ok else -1


## Wait physics frames until `done` holds or `limit` frames passed.
func until(done: Callable, limit: int) -> void:
	for _frame in limit:
		if done.call():
			return
		await physics_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
