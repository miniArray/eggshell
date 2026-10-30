extends SceneTree
## Invented geometry. Eligibility, same-tag ordering and surviving lifetimes are separate.
const Fixtures = preload("res://tests/knockback_completion.gd")
const Registry = preload("res://src/sim/registry.gd")
const Knockback = preload("res://src/sim/knockback.gd")
const Armor = preload("res://src/sim/types/armored_walker.gd")
const Soft = preload("res://src/sim/types/soft_walker.gd")
const Sim = preload("res://src/sim/step.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const S := 3600
var checks := 0
var failures := 0


func _initialize() -> void:
	for code: String in ["e11", "e23"]:
		survivor_and_opposite_burst(code)
		active_precedes_waiting(code)
		waiting_release_order(code)
		stop_fallback_and_release(code)
		many_overlapping_tweens(code)
		invalid_collections(code)
	later_survivor_completion()
	collection_schema()
	codec_count_bound()
	print("KNOCKBACK_LIFETIME_RESULT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func burst(unit: Dictionary, direction: int) -> void:
	var owner: Dictionary = unit.older
	if owner.code == "e11":
		Armor.knockback(owner, unit.state, unit.world, owner.x - direction * 80 * S, false)
	else:
		var source := Registry.spawn_dynamic(
			unit.state, unit.world, "e23", owner.x - direction * 80 * S, owner.y, {"can_despawn": 0}
		)
		Soft.burst(source, unit.state, unit.world)


func restored(unit: Dictionary) -> Dictionary:
	var bytes := Snapshot.encode(unit.state)
	check(not bytes.is_empty(), "Ordered tween collection saves: " + Snapshot.refusal(unit.state))
	var replay := Fixtures.fixture(unit.older.code)
	var decoded := Snapshot.decode(bytes, unit.state.identity, replay.world)
	check(decoded.ok, "The typed collection restores with the world")
	if decoded.ok:
		replay.state = decoded.state
		replay.older = Registry.find_token(decoded.state, unit.older.token)
	return replay


func same_future(unit: Dictionary, replay: Dictionary, ticks: int = 6) -> void:
	for tick in ticks:
		Sim.advance(unit.state, 0, unit.world)
		Sim.advance(replay.state, 0, replay.world)
		var bytes := Snapshot.encode(unit.state)
		check(not bytes.is_empty(), "The overlapping tween future stays valid")
		check(bytes == Snapshot.encode(replay.state), "Ordered lifetime and motion replay exactly")


func survivor_and_opposite_burst(code: String) -> void:
	var unit := Fixtures.fixture(code)
	Registry.advance(unit.state, unit.world, 0)
	check(Knockback.pending(unit.older), "The oldest tween reaches its natural endpoint")
	burst(unit, 1)
	check(unit.older.knock_tweens.size() == 2, "Global98 appends instead of replacing the old tag")
	check(Knockback.value(unit.older) == 0, "The endpoint zero stays first during regular events")
	var replay := restored(unit)
	Registry.after_step(unit.state, unit.world)
	Registry.after_step(replay.state, replay.world)
	check(unit.older.knock_active == 0, "Global102 clears only eligibility")
	check(
		Fixtures.active_rows(unit.older).size() == 1,
		"The same-tag replacement survives old completion"
	)
	check(
		unit.older.knock_tweens.size() == 2,
		"The completed old row waits for next behavior tick2 release"
	)
	check(Knockback.value(unit.older) == 448 * 60, "Value(tag) reads the survivor while ineligible")
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(replay.state),
		"Completion preserves the same survivor after restore"
	)
	Sim.advance(unit.state, 0, unit.world)
	check(unit.older.knock_tweens[0].remaining == 59, "The survivor keeps ticking while ineligible")
	check(unit.older.knock_active == 0, "Lifetime advancement does not reactivate the owner")
	burst(unit, -1)
	check(
		unit.older.knock_tweens.size() == 2, "The subsequent opposite burst appends another tween"
	)
	check(
		Knockback.value(unit.older) == 448 * 59,
		"GetTweenValue still reads the older positive survivor"
	)
	var type: Script = Registry.lookup(code)
	type.after_advance(unit.state, unit.world)
	check(
		unit.older.vx == 448 * 59,
		"Reactivated family events assign the survivor, not the new opposite sign"
	)
	replay = restored(unit)
	same_future(unit, replay)


func active_precedes_waiting(code: String) -> void:
	var unit := Fixtures.fixture(code)
	Fixtures.configure_tween(unit.older, 30, 448 * 60)
	Knockback.stop(unit.older)
	check(
		Knockback.value(unit.older) == 448 * 30,
		"Without active matches, Value falls back to waiting releases"
	)
	burst(unit, -1)
	check(unit.older.knock_tweens.size() == 2, "Stop retains its waiting row until behavior tick2")
	check(
		Knockback.value(unit.older) == -448 * 60,
		"An active replacement precedes the older waiting-release row"
	)
	var replay := restored(unit)
	Registry.after_step(unit.state, unit.world)
	Registry.after_step(replay.state, replay.world)
	check(
		unit.older.knock_tweens.size() == 1 and unit.older.knock_active == 1,
		"Release removes only the stopped row; replacement stays eligible"
	)
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(replay.state),
		"Active-before-waiting selection restores"
	)
	same_future(unit, replay, 3)


func waiting_release_order(code: String) -> void:
	var unit := Fixtures.fixture(code)
	Fixtures.configure_tween(unit.older, 30, 448 * 60)
	Knockback.start(unit.older, -448 * 60, 60)
	unit.older.knock_tweens[1].remaining = 1
	unit.older.knock_tweens[1].phase = Knockback.PLAYING
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.older.knock_tweens[1].phase == Knockback.FINISHED_WAITING,
		"A newer short tween can finish before its older survivor"
	)
	Knockback.stop(unit.older)
	check(
		Knockback.value(unit.older) == 0,
		"Waiting lookup uses release order, not flat registration order"
	)
	check(
		unit.older.knock_tweens[0].remaining == 0,
		"The earlier natural release precedes the newly stopped positive tween"
	)
	var replay := restored(unit)
	Registry.after_step(unit.state, unit.world)
	Registry.after_step(replay.state, replay.world)
	check(
		unit.older.knock_tweens.is_empty(), "The next behavior tick2 releases both waiting classes"
	)
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(replay.state),
		"Waiting release order survives save and restore"
	)


func stop_fallback_and_release(code: String) -> void:
	var unit := Fixtures.fixture(code)
	Registry.advance(unit.state, unit.world, 0)
	Knockback.stop(unit.older)
	check(not Knockback.pending(unit.older), "Stop suppresses the endpoint's queued completion")
	check(
		Knockback.value(unit.older) == 0,
		"Stopped endpoint remains the waiting fallback value until release"
	)
	var replay := restored(unit)
	Registry.after_step(unit.state, unit.world)
	Registry.after_step(replay.state, replay.world)
	check(unit.older.knock_tweens.is_empty(), "Behavior tick2 releases the stopped tween")
	check(unit.older.knock_active == 1, "Stop alone does not run Global102 or clear its flag")
	check(
		Snapshot.encode(unit.state) == Snapshot.encode(replay.state),
		"Suppressed completion restores without firing"
	)
	var x: int = unit.older.x
	same_future(unit, replay, 2)
	check(
		unit.older.x == x and unit.older.vx == 0,
		"Eligibility remains distinct from an empty lifetime collection after Stop"
	)


func many_overlapping_tweens(code: String) -> void:
	var unit := Fixtures.fixture(code)
	Knockback.clear(unit.older)
	for index in 17:
		burst(unit, 1 if index % 2 == 0 else -1)
	check(
		unit.older.knock_tweens.size() == 17,
		"There is no two-tween or other invented gameplay count cap"
	)
	check(
		Knockback.value(unit.older) == 448 * 60,
		"Arbitrarily many registrations preserve the first active match"
	)
	var replay := restored(unit)
	check(
		replay.older.knock_tweens == unit.older.knock_tweens,
		"All ordered rows round trip, not just the first two"
	)
	same_future(unit, replay, 2)


func later_survivor_completion() -> void:
	var unit := Fixtures.fixture()
	Fixtures.configure_tween(unit.older, 1, 448 * 60)
	Knockback.start(unit.older, -448 * 60, 60)
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.older.knock_active == 0 and Fixtures.active_rows(unit.older).size() == 1,
		"An endpoint removes only its own active row"
	)
	check(
		Knockback.value(unit.older) == -448 * 59,
		"A replacement advances independently during the older endpoint"
	)
	unit.older.knock_tweens[0].remaining = 1
	burst(unit, 1)
	Sim.advance(unit.state, 0, unit.world)
	check(
		unit.older.knock_active == 0 and Fixtures.active_rows(unit.older).size() == 1,
		"The next natural finish also preserves its replacement"
	)
	burst(unit, -1)
	check(
		Knockback.value(unit.older) == 448 * 59,
		"The third burst still reads the surviving positive tween first"
	)
	var replay := restored(unit)
	same_future(unit, replay, 3)


func invalid_collections(code: String) -> void:
	var unit := Fixtures.fixture(code)
	check(Registry.valid(unit.older), "The owner and typed tween row are valid")
	for field: String in ["from_vx", "remaining", "total", "phase"]:
		var bad: Dictionary = unit.older.duplicate(true)
		bad.knock_tweens[0][field] = "1"
		check(not Registry.valid(bad), "Collection row fields must be int64: " + field)
	for pair: Array in [
		["remaining", -1],
		["remaining", 61],
		["total", 0],
		["phase", 4],
		["from_vx", Knockback.MAX_SPEED + 1],
		["from_vx", -9223372036854775807 - 1]
	]:
		var bad: Dictionary = unit.older.duplicate(true)
		bad.knock_tweens[0][pair[0]] = pair[1]
		check(not Registry.valid(bad), "Reject inconsistent lifetime row: " + str(pair))
	var malformed: Dictionary = unit.older.duplicate(true)
	malformed.knock_tweens = [17]
	check(not Registry.valid(malformed), "Reject non-row collection entries")
	malformed = unit.older.duplicate(true)
	malformed.knock_tweens[0].extra = 0
	check(not Registry.valid(malformed), "Reject undeclared row fields")
	malformed = unit.older.duplicate(true)
	malformed.knock_tweens[0].phase = Knockback.SCHEDULED
	check(
		not Registry.valid(malformed),
		"A scheduled tween must retain its initial remaining duration"
	)
	malformed = unit.older.duplicate(true)
	malformed.knock_active = 2
	check(not Registry.valid(malformed), "Eligibility is an independent int64 boolean")


func collection_schema() -> void:
	var schema := Registry.collection_fields("e11")
	check(
		is_same(schema, Registry.collection_fields("e11")),
		"Collection declarations reuse the cached type constant"
	)
	check(
		schema.is_read_only() and schema[0][1][0].is_read_only(),
		"Collection declarations are recursively read-only"
	)
	check(schema == Registry.collection_fields("e23"), "Both owners use one typed row schema")


func codec_count_bound() -> void:
	var unit := Fixtures.fixture()
	var bytes := Snapshot.encode(unit.state)
	var body := bytes.slice(0, -Snapshot.CHECKSUM_SIZE)
	var cursor := Snapshot.count_offset() + 4
	for entity: Dictionary in unit.state.entities:
		var code := Snapshot.read_text(body, cursor, body.size())
		var id := Snapshot.read_text(body, code.cursor, body.size())
		cursor = id.cursor + 4 + Registry.fields(entity.code).size() * 8
		for collection: Array in Registry.collection_fields(entity.code):
			if entity.token == unit.older.token:
				var invalid_phase := body.duplicate()
				invalid_phase.encode_s64(cursor + 4 + 3 * 8, 4)
				invalid_phase.append_array(Snapshot.checksum(invalid_phase))
				check(
					not Snapshot.decode(invalid_phase, unit.state.identity, unit.world).ok,
					"Checksum-valid invalid row phases fail domain validation"
				)
				body.encode_u32(cursor, 0xffffffff)
				body.append_array(Snapshot.checksum(body))
				check(
					not Snapshot.decode(body, unit.state.identity, unit.world).ok,
					"Payload bounds reject an oversized collection count before allocation"
				)
				return
			cursor += 4 + entity[collection[0]].size() * collection[1].size() * 8
	check(false, "The serialized owner collection exists")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)
