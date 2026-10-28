extends SceneTree
## Sound derivation from synthetic state pairs. No level, scene or audio output is used.
const Player = preload("res://src/view/audio_player.gd")
const AudioMap = preload("res://src/view/pack_audio.gd")
const Settings = preload("res://src/save/settings.gd")
const Life = preload("res://src/sim/life.gd")
const Moves = preload("res://src/sim/moves.gd")
const Requests = preload("res://src/sim/move_requests.gd")
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Sim = preload("res://src/sim/step.gd")
const Bits = preload("res://src/sim/move_input.gd")
const CollisionTable = preload("res://src/level/collision_table.gd")
var _failures := 0
var _checks := 0


func _initialize() -> void:
	derivation_checks()
	object_checks()
	life_checks()
	level_checks()
	map_checks()
	track_checks()
	settings_checks()
	observer_checks()
	simulation_checks()
	print("Audio: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


static func base() -> Dictionary:
	return Player.summarize({"frame": 100})


static func after(previous: Dictionary, changes: Dictionary) -> Dictionary:
	var current := previous.duplicate()
	current.frame = previous.frame + 1
	for key: String in changes:
		current[key] = changes[key]
	return current


static func events(cues: Array) -> Array:
	var result := []
	for cue: Dictionary in cues:
		result.append(cue.get("event", cue.get("role", cue.cue)))
	return result


func expect(changes: Dictionary, expected: Array, label: String, start := {}) -> void:
	var previous := base()
	for key: String in start:
		previous[key] = start[key]
	var got := events(
		Player.derive(previous, after(previous, changes), {"redcoins": 5, "flowers": 5})
	)
	check(got == expected, "%s: expected %s, got %s" % [label, expected, got])


func derivation_checks() -> void:
	var idle := base()
	check(Player.derive(idle, after(idle, {}), {}).is_empty(), "an unchanged step is silent")
	check(idle.health == 10 and idle.map_index == 1, "missing fields read their defaults")
	expect({"vy": -46000, "move_pound_delay": 6}, ["jump"], "jump from rest", {"on_floor": 1})
	expect(
		{"vy": -40000, "boosted_flutter": 1, "move_pound_delay": 6},
		["stomp"],
		"enemy bounce is a stomp, not a jump",
		{"vy": 3000}
	)
	expect(
		{"vy": -60480, "boosted_flutter": 1, "switch_sound_serial": 2, "switch_sound_kind": 2},
		["switch_timer"],
		"switch launch is neither a jump nor a stomp",
		{"switch_sound_serial": 1}
	)
	expect(
		{"vy": -23040, "invulnerable": 120, "move_pound_delay": 6},
		["hit"],
		"damage knockback is a hit, not a jump"
	)
	expect({"flutter_remaining": 40}, ["flutter"], "flutter start")
	expect({"flutter_remaining": 39}, [], "flutter continues silently", {"flutter_remaining": 40})
	expect({"move_action": Moves.POUND_START}, ["pound_start"], "pound start")
	expect({"move_impact": 1}, ["pound_land"], "pound landing")
	expect({"move_action": Moves.TONGUE}, ["tongue"], "tongue")
	expect({"move_action": Moves.TOSS}, ["egg_throw"], "toss")
	expect({"move_action": Moves.HEAD_BUMP}, ["head_bump"], "head bump")
	expect({"swimming": 1}, ["splash"], "water entry")
	expect({"swimming": 0}, ["splash"], "water exit", {"swimming": 1})
	expect({"move_eggs": 2}, ["egg_pickup"], "egg pickup", {"move_eggs": 1})
	expect(
		{"move_eggs": 2, "move_emit_serial": 1, "move_emit_kind": Requests.STORED_EGG},
		["egg_made"],
		"a digested egg is not a pickup",
		{"move_eggs": 1}
	)
	expect(
		{
			"move_emit_serial": 3,
			"move_emit_kind": Requests.COLD,
			"move_emit_1_kind": Requests.HEAT,
			"move_emit_2_kind": Requests.SPIT
		},
		["spit_ice", "spit_fire"],
		"only requests newer than the previous serial sound",
		{"move_emit_serial": 1, "move_emit_kind": Requests.SPIT}
	)
	expect(
		{"move_emit_serial": 2, "move_emit_kind": Requests.SEED},
		["spit_seed"],
		"seed",
		{"move_emit_serial": 1}
	)
	expect(
		{"move_emit_serial": 0, "move_emit_kind": 0},
		[],
		"a cleared request history is silent",
		{"move_emit_serial": 4, "move_emit_kind": Requests.SPIT}
	)
	var aiming := base()
	aiming.move_aim = 1
	aiming.frame = 102
	var ticks := 0
	for step in 8:
		var next := after(aiming, {})
		ticks += events(Player.derive(aiming, next, {})).count("aim_tick")
		aiming = next
	check(ticks == 2, "aim ticks every four frames, got %d" % ticks)
	expect({"coins": 1}, ["coin"], "coin")
	expect({"redcoins": 3}, ["red_coin"], "red coin", {"redcoins": 2})
	expect({"redcoins": 5}, ["all_red_coins"], "last red coin", {"redcoins": 4})
	expect({"flowers": 2}, ["flower"], "flower", {"flowers": 1})
	expect({"flowers": 5}, ["flower", "all_flowers"], "last flower", {"flowers": 4})
	expect(
		{"switch_sound_serial": 4, "switch_sound_kind": 1},
		["switch_press"],
		"switch press",
		{"switch_sound_serial": 3}
	)
	var stop := Player.derive(
		base(), after(base(), {"switch_sound_serial": 1, "switch_sound_kind": 3}), {}
	)
	check(stop == [{"cue": "stop_effect", "event": "switch_timer"}], "switch end stops the timer")
	expect({"message_stage": 1}, ["message_hit"], "message hit")
	expect({"message_stage": 2}, ["message_open"], "message open", {"message_stage": 1})
	expect({"message_section": 1}, ["message_scroll"], "message scroll", {"message_stage": 2})
	expect({"message_stage": 3}, ["message_close"], "message close", {"message_stage": 2})
	expect(
		{"move_snow": 1, "on_floor": 1, "vx": 3000, "frame": 108},
		["snow_step"],
		"snow footstep on its period",
		{"frame": 107}
	)


func object_checks() -> void:
	var rows := [
		{"code": "o7", "token": 1000001, "mode": 1, "bounces": 4},
		{"code": "o8", "token": 2, "phase": 0, "status": 1, "content": 2},
		{"code": "o8", "token": 3, "phase": 1, "status": 1, "content": 1},
		{"code": "o9", "token": 4, "busy": 7},
		{"code": "o11", "token": 5, "squash": 0},
		{"code": "o31", "token": 6, "opened": 0},
		{"code": "e4", "token": 7, "status": 1}
	]
	var state := {"frame": 50, "entities": rows}
	var before := Player.summarize(state)
	check(before.objects.size() == 6 and before.eggs == 1, "watched object rows summarized")
	state = state.duplicate(true)
	state.frame = 51
	state.entities[0].bounces = 3
	state.entities[1].phase = 2
	state.entities[2].phase = 3
	state.entities[3].busy = 6
	state.entities.append({"code": "o7", "token": 1000002, "mode": 1, "bounces": 4})
	state.entities[4].squash = 12
	state.entities[5].opened = 1
	var heard := events(Player.derive(before, Player.summarize(state)))
	check(
		(
			heard
			== [
				"egg_bounce",
				"egg_ricochet",
				"cloud_reveal",
				"cloud_hit",
				"egg_block",
				"spring",
				"gate_open"
			]
		),
		"object changes: %s" % [heard]
	)
	before = Player.summarize(state)
	state.frame = 52
	state.entities[2].status = 3
	state.entities[4].squash = 11
	check(
		events(Player.derive(before, Player.summarize(state))) == ["cloud_release"],
		"a cache release with stars or coins"
	)
	var replaced := state.duplicate(true)
	replaced.frame = 53
	replaced.entities[0].code = "o9"
	replaced.entities[0].busy = 0
	check(
		Player.derive(Player.summarize(state), Player.summarize(replaced)).is_empty(),
		"a reused token with another code is silent"
	)


func life_checks() -> void:
	expect({"life_phase": Life.DEAD}, ["stop_all", "death"], "death stops all and plays a role")
	expect({"life_phase": Life.FADE_OUT}, ["stop_all", "quick_death"], "quick death")
	expect(
		{"life_phase": Life.FADE_OUT}, [], "fade after death is silent", {"life_phase": Life.DEAD}
	)
	expect({"life_phase": Life.GOAL}, ["stop_music", "goal"], "goal")
	expect({"life_phase": Life.REJOIN}, ["rescue"], "rescue")
	expect({"life_phase": Life.PLAY}, ["rejoin"], "rejoin", {"life_phase": Life.REJOIN})
	expect(
		{"life_phase": Life.FADE_IN, "redcoins": 0, "flowers": 0, "health": 10, "swimming": 0},
		[],
		"respawn rollback is silent",
		{"life_phase": Life.FADE_OUT, "redcoins": 3, "flowers": 2, "health": 4, "swimming": 1}
	)
	expect(
		{"health": 9, "health_wait": 45},
		["countdown_low"],
		"countdown below ten",
		{"separated": 1, "health": 10, "health_wait": 1}
	)
	expect(
		{"health": 11, "health_wait": 45},
		["countdown_high"],
		"countdown from a high count",
		{"separated": 1, "health": 12, "health_wait": 1}
	)
	expect(
		{"health": 10, "health_wait": 0},
		["countdown_full"],
		"regeneration reaches ten",
		{"health": 9, "health_wait": 1}
	)
	expect(
		{"health": 9, "health_wait": 119},
		[],
		"regeneration below ten is silent",
		{"health": 8, "health_wait": 1}
	)
	expect({"health": 11}, ["star"], "star pickup")
	expect({"health": 12}, ["star"], "star pickup while separated", {"health": 11, "separated": 1})
	expect(
		{"life_phase": Life.CHECKPOINT, "health": 11, "checkpoint_awards": 9, "life_ticks": 6},
		["star"],
		"checkpoint award",
		{"life_phase": Life.CHECKPOINT, "health": 10, "checkpoint_awards": 10, "life_ticks": 0}
	)
	expect(
		{"life_phase": Life.CHECKPOINT, "health": 20, "checkpoint_awards": 0, "life_ticks": 45},
		["checkpoint"],
		"last award clears the checkpoint without a star",
		{"life_phase": Life.CHECKPOINT, "health": 19, "checkpoint_awards": 1, "life_ticks": 0}
	)
	expect(
		{"companion_mode": Life.BUBBLE},
		["companion_cry"],
		"companion enters the bubble",
		{"companion_mode": Life.LAUNCH}
	)


func level_checks() -> void:
	var audio := AudioMap.new()
	audio.setup(
		{
			"audio":
			{
				"music":
				{
					"1": {"file": "audio/one.ogg", "loop_start": 1.5, "volume_db": -2},
					"named": "audio/named.ogg"
				}
			}
		},
		"/pack"
	)
	var world := {
		"maps":
		{
			1: {"music": {"id": "1", "settings": "0,0", "custom": false}},
			2: {"music": {"id": "0", "settings": "0,0", "custom": false}},
			3:
			{"music": {"id": "https://example.invalid/a.ogg", "settings": "2,-5", "custom": true}},
			4: {"music": {"id": "named", "settings": "2.5,-5", "custom": true}}
		}
	}
	check(
		Player.level_track(world, 1, audio) == {"key": "1", "loop_start": 1.5, "volume_db": -2.0},
		"built-in track uses pack settings"
	)
	check(Player.level_track(world, 2, audio).is_empty(), "unknown id is silent")
	check(Player.level_track(world, 3, audio).is_empty(), "remote music is never fetched")
	check(
		(
			Player.level_track(world, 4, audio)
			== {"key": "named", "loop_start": 2.5, "volume_db": -5.0}
		),
		"custom selection uses level settings"
	)
	check(Player.level_track({}, 1, audio).is_empty(), "missing music is silent")


func map_checks() -> void:
	var audio := AudioMap.new()
	check(audio.is_empty(), "a new map is empty")
	audio.setup(
		{
			"audio":
			{
				"music":
				{
					"1": {"file": "audio/a.ogg", "loop_start": -1, "volume_db": "loud"},
					"2": {"file": "../escape.ogg"},
					"3": "audio/c.wav",
					"4": {"loop_start": 3}
				},
				"effects": {"hop": "audio/hop.ogg", "bad": 7},
				"events":
				{
					"jump": "hop",
					"turns": ["a", "b", "c"],
					"empty": "",
					"number": 3,
					"mixed": ["a", 4]
				},
				"tracks": {"goal": "4"}
			}
		},
		"/pack"
	)
	check(audio.music.keys() == ["1"], "unsafe, non-Ogg and file-less tracks dropped")
	check(audio.music["1"] == "/pack/audio/a.ogg", "track path joined to the pack")
	check(
		audio.settings_for("1") == {"loop_start": 0.0, "volume_db": 0.0},
		"invalid track settings fall back"
	)
	check(audio.effects.keys() == ["hop"], "invalid effects dropped")
	check(audio.effect_key("jump") == "hop", "mapped event")
	check(audio.effect_key("coin") == "coin", "unmapped event falls back to its own name")
	check(audio.effect_key("empty") == "empty", "empty mapping ignored")
	check(audio.effect_key("mixed") == "mixed", "a list with a non-key is ignored")
	check(
		(
			[0, 1, 2, 3, -1].map(func(pick: int) -> String: return audio.effect_key("turns", pick))
			== ["a", "b", "c", "a", "c"]
		),
		"a key list takes turns by pick"
	)
	check(audio.track_key("goal") == "4" and audio.track_key("death") == "death", "music roles")
	check(audio.stream("music", "missing") == null, "missing key has no stream")
	check(audio.stream("other", "1") == null, "unknown section has no stream")
	audio.setup({"audio": ["wrong"]}, "/pack")
	check(audio.is_empty() and audio.events.is_empty(), "bad audio section clears the map")


func track_checks() -> void:
	var player: Node = Player.create(AudioMap.new(), {}, {}, false)
	check(player.get_child_count() == 0, "a pack without audio creates no players")
	player.free()


func settings_checks() -> void:
	var directory := "/tmp/eggshell-audio-settings-%d" % OS.get_process_id()
	var path := directory.path_join("settings.json")
	var created := Settings.read_or_create(directory)
	check(
		created.error == "" and created.music_volume == 80 and created.effects_volume == 80,
		"new settings use volume defaults"
	)
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(written is Dictionary and written.get("music_volume") == 80.0, "defaults are written")
	write(path, {"version": 1, "resume_where_i_left_off": false})
	var old := Settings.read_or_create(directory)
	check(
		old.error == "" and not old.resume and old.music_volume == 80,
		"settings without volumes keep working"
	)
	write(
		path,
		{"version": 1, "resume_where_i_left_off": true, "music_volume": 0, "effects_volume": 100}
	)
	var edges := Settings.read_or_create(directory)
	check(edges.music_volume == 0 and edges.effects_volume == 100, "volume bounds accepted")
	for bad: Variant in [-1, 101, 50.5, "60", true, null]:
		write(path, {"version": 1, "resume_where_i_left_off": true, "effects_volume": bad})
		var result := Settings.read_or_create(directory)
		check(
			result.effects_volume == 80 and not result.error.is_empty(),
			"invalid volume falls back: %s" % str(bad)
		)
	write(path, {"version": 2})
	var invalid := Settings.read_or_create(directory)
	check(invalid.resume and invalid.music_volume == 80, "invalid file uses all defaults")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func observer_checks() -> void:
	var player: Node = Player.create(AudioMap.new(), {"redcoins_target": 2}, {}, true)
	var state := {"frame": 10, "coins": 0}
	player.observe(state)
	check(player.last_cues.is_empty(), "the first observation only synchronizes")
	state.frame = 11
	state.coins = 1
	player.observe(state)
	check(events(player.last_cues) == ["coin"], "a continuous step derives cues")
	var restored := {"frame": 12, "coins": 5, "redcoins": 2}
	player.observe(restored)
	check(player.last_cues.is_empty(), "a replaced state never replays sounds")
	restored.frame = 13
	restored.redcoins = 3
	player.observe(restored)
	check(events(player.last_cues) == ["all_red_coins"], "play continues after a restore")
	restored.frame = 40
	restored.coins = 6
	player.observe(restored)
	check(player.last_cues.is_empty(), "a jump in time resynchronizes")
	restored.frame = 30
	restored.coins = 7
	player.observe(restored)
	check(player.last_cues.is_empty(), "time going back resynchronizes")
	player.free()


func simulation_checks() -> void:
	# The real fixed step feeds the observer, as the game does after each step.
	var code := FileAccess.get_file_as_string("res://tests/fixtures/lagoon.level.json")
	var built := World.build(code, CollisionTable.read())
	check(built.ok, "fixture level builds")
	if not built.ok:
		return
	var world: Dictionary = built.world
	var state := State.create(world)
	var player: Node = Player.create(AudioMap.new(), world, {}, true)
	var heard := []
	var script := [[0, 90], [Bits.JUMP, 40], [0, 60], [Bits.JUMP, 2], [0, 14], [Bits.DOWN, 60]]
	for part: Array in script:
		for count in part[1]:
			Sim.advance(state, part[0], world)
			player.observe(state)
			heard.append_array(events(player.last_cues))
	for event: String in ["jump", "flutter", "pound_start", "pound_land"]:
		check(event in heard, "real steps derive %s: %s" % [event, heard])
	check(heard.count("jump") == 2, "each jump sounds once: %s" % [heard])
	check(not "stomp" in heard and not "hit" in heard, "no false contact sounds: %s" % [heard])
	player.free()


func write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
