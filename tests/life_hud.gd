extends SceneTree
## HUD policy and font metadata only. No frames are rendered.

const Hud = preload("res://src/view/hud.gd")
const Life = preload("res://src/sim/life.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	var font := ThemeDB.fallback_font
	for count: int in [0, 1, 9223372036854775807]:
		var state := {
			"health": 10,
			"coins": count,
			"redcoins": count,
			"flowers": count,
			"redcoins_target": 2147483647,
			"flowers_target": 2147483647,
			"life_phase": Life.PLAY,
			"separated": 1
		}
		var before := state.duplicate(true)
		var rows := Hud.readouts(state)
		check(rows.size() == 5, "Four counters and the rescue status remain available")
		check(state == before, "HUD policy does not mutate simulation state")
		var widths: Array[float] = []
		for row: Dictionary in rows:
			widths.append(font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		for size: Vector2 in [
			Vector2(832, 448),
			Vector2(640, 480),
			Vector2(480, 480),
			Vector2(1280, 720),
			Vector2(1280, 80),
			Vector2(170, 1280),
			Vector2(80, 80),
			Vector2(1, 1)
		]:
			var plan := Hud.plan(size, widths)
			check(plan.positions.size() == rows.size(), "Every readout survives container reflow")
			check(
				plan.size.x <= size.x and plan.size.y <= size.y * 0.4 + 0.001,
				"HUD remains within its container budget"
			)
			var scale: float = plan.scale
			check(
				(
					is_equal_approx(scale, floorf(scale))
					if scale >= 1
					else is_equal_approx(1 / scale, floorf(1 / scale))
				),
				"HUD uses pixel-aligned scale factors"
			)
			for index in widths.size():
				var point: Vector2 = plan.positions[index]
				check(
					(
						point.x >= 0
						and point.y >= 0
						and (point.x + widths[index]) * scale <= size.x + 0.001
					),
					"Readout has no horizontal clipping"
				)
	check(
		Hud.plan(Vector2.ZERO, [100.0]).is_empty(),
		"A zero-sized container draws nothing until it has space"
	)
	var complete := {"health": 30, "redcoins": 20, "flowers": 5, "life_phase": Life.COMPLETE}
	check(
		Hud.readouts(complete)[-1].text == "Complete  Score 100",
		"Final score comes only from state"
	)
	complete.hits = 4
	complete.deaths = 2
	complete.total_play_ticks = 3661 * 60 + 29
	var score_rows := Hud.readouts(complete)
	check(score_rows.size() == 7, "Score phase keeps all counters and adds run statistics")
	check(
		score_rows[4].text == "Hurt 4  Deaths 2",
		"Score statistics use the saved hit and death counts"
	)
	check(score_rows[5].text == "Time 01:01:01.48", "Total time is formatted from integer ticks")
	check(Hud.clock_text(-1) == "00:00:00.00", "Clock display clamps negative input")
	check(
		not Hud.clock_text(9223372036854775807).is_empty(),
		"Clock formatting does not multiply an unbounded counter"
	)
	var score_widths: Array[float] = []
	for row: Dictionary in score_rows:
		score_widths.append(font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
	for size: Vector2 in [Vector2(832, 448), Vector2(170, 1280), Vector2(1280, 80), Vector2(1, 1)]:
		var score_plan := Hud.plan(size, score_widths)
		check(
			(
				score_plan.positions.size() == 7
				and score_plan.size.x <= size.x
				and score_plan.size.y <= size.y * 0.4 + 0.001
			),
			"Score statistics reflow without hiding a counter (%s -> %s)" % [size, score_plan.size]
		)
	var font_info := {
		"file": "fonts/unit.png",
		"characters": "0123456789",
		"cell_width": 8,
		"cell_height": 12,
		"widths": []
	}
	check(Hud.bitmap_ok(font_info), "Valid bitmap glyph metadata")
	for pair: Array in [
		["file", "../outside.png"],
		["cell_width", 0],
		["cell_height", "bad"],
		["characters", ""],
		["widths", [[-1, "1"]]],
		["widths", [[8, 1]]]
	]:
		var invalid := font_info.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(not Hud.bitmap_ok(invalid), "Invalid optional font metadata is rejected")
	print("LIFE_HUD_RESULT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
