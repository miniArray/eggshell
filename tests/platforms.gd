extends SceneTree
## Pure synthetic solids, carry and callback checks. No game scene or rendering.
const Collision = preload("res://src/sim/collision.gd")
const Registry = preload("res://src/sim/registry.gd")
const State = preload("res://src/sim/play_state.gd")
const Snapshot = preload("res://src/save/snapshot.gd")
const Sim = preload("res://src/sim/step.gd")
const World = preload("res://src/sim/world.gd")
const Screen = preload("res://src/sim/screen.gd")
const Shapes = preload("res://tests/platform_shapes.gd")
const S := 3600
const BOX := [-4 * S, -8 * S, 4 * S, 0]
const GAP := S / 16
var checks := 0
var failures := 0


func _initialize() -> void:
	full_checks()
	one_way_checks()
	strip_checks()
	carry_checks()
	callback_checks()
	span_type_checks()
	crumble_type_checks()
	block_type_checks()
	redirect_type_checks()
	gate_type_checks()
	post_type_checks()
	cache_type_checks()
	switch_type_checks()
	shared_interaction_checks()
	print("PLATFORMS_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func full_checks() -> void:
	var entity := solid("unit-full", 64 * S, 64 * S)
	var state := player([entity], 64 * S, 56 * S - GAP)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	check(Collision.floor_at(state, world, BOX) != 0, "full entity supplies floor support")
	check(not Collision.overlaps(state, world, BOX), "standing gap is free")
	check(
		not Collision.overlaps(entity, world, [-16 * S, -8 * S, 16 * S, 8 * S]),
		"solid body never collides with itself"
	)
	state.x = 44 * S - GAP
	state.y = 64 * S
	state.vx = 4 * S
	var moved := Collision.horizontal(state, world, BOX, 4 * S, 0)
	check(moved < 4 * S and state.vx == 0, "full entity blocks side entry")
	var actor := {"x": 64 * S, "y": 50 * S, "vx": 0, "vy": 12 * S}
	moved = Collision.vertical(actor, world, BOX, 12 * S)
	check(moved < 12 * S and actor.vy == 0, "terrain-aware actor lands on entity")
	state.x = 64 * S
	state.y = 60 * S
	check(Collision.overlaps(state, world, BOX), "active volume is in the collision query")
	entity.status = 3
	check(not Collision.overlaps(state, world, BOX), "inactive entity does not block")
	entity.status = 1
	entity.broken = 1
	check(
		not Collision.overlaps(state, world, BOX),
		"empty provider disables an otherwise active solid"
	)


func one_way_checks() -> void:
	var state := player([solid("unit-top", 64 * S, 64 * S)], 64 * S, 56 * S)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	state.vy = 12 * S
	check(
		Collision.vertical(state, world, BOX, 12 * S) < 12 * S,
		"top-only entity catches downward entry"
	)
	state.y = 70 * S
	state.vy = -16 * S
	check(
		Collision.vertical(state, world, BOX, -16 * S) == -16 * S,
		"top-only entity permits upward entry"
	)
	state.x = 40 * S
	state.y = 68 * S
	state.vx = 20 * S
	check(
		Collision.horizontal(state, world, BOX, 20 * S, 0) == 20 * S,
		"top-only entity permits side entry from below"
	)
	check(Collision.floor_at(state, world, BOX) == 0, "top-only overlap is not a floor from below")


func strip_checks() -> void:
	var state := player([solid("unit-strips", 96 * S, 64 * S)], 96 * S, 56 * S)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	state.vy = 16 * S
	check(
		Collision.vertical(state, world, BOX, 16 * S) == 16 * S,
		"plural strips retain the open middle gap"
	)
	check(
		not Collision.support_in_box(world, 92 * S, 60 * S, 100 * S, 90 * S),
		"edge probe sees the same strip gap"
	)
	check(
		Collision.support_in_box(world, 60 * S, 60 * S, 68 * S, 90 * S),
		"edge probe includes registered support"
	)
	state.x = 64 * S
	state.y = 56 * S
	state.vy = 16 * S
	check(Collision.vertical(state, world, BOX, 16 * S) < 16 * S, "left strip supplies a landing")
	state.x = 128 * S
	state.y = 64 * S - GAP
	check(Collision.floor_at(state, world, BOX) != 0, "right strip supplies support independently")


func carry_checks() -> void:
	var entity := solid("unit-top", 64 * S, 64 * S)
	var state := player([entity], 64 * S, 64 * S - GAP)
	state.on_floor = 1
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	entity.x += 3 * S
	entity.y -= 2 * S
	check(Collision.prepare(state, world, BOX), "carried player remains in free space")
	check(
		state.x == 67 * S and state.y == 62 * S - GAP,
		"carry applies both platform axes before floor handling"
	)
	Collision.prepare(state, world, BOX)
	check(state.x == 67 * S, "multiple prepare calls do not repeat carry")
	var restored := state.duplicate(true)
	var clean_world := geometry()
	state.frame += 1
	restored.frame += 1
	Collision.begin_step(state, world, Shapes)
	Collision.begin_step(restored, clean_world, Shapes)
	state.entities[0].x += 2 * S
	restored.entities[0].x += 2 * S
	Collision.prepare(state, world, BOX)
	Collision.prepare(restored, clean_world, BOX)
	check(state == restored, "fresh per-step bindings reproduce restored carry")
	state.vy = -S
	state.frame += 1
	Collision.begin_step(state, world, Shapes)
	state.entities[0].x += 4 * S
	var x: int = state.x
	Collision.prepare(state, world, BOX)
	check(state.x == x, "rising player does not ride the old support")
	var platform := solid("unit-top", 64 * S, 64 * S)
	var wall := solid("unit-full", 96 * S, 56 * S)
	wall.id = "wall"
	state = player([platform, wall], 64 * S, 64 * S - GAP)
	state.on_floor = 1
	world = geometry()
	Collision.begin_step(state, world, Shapes)
	platform.x += 20 * S
	Collision.prepare(state, world, BOX)
	check(
		not Collision.overlaps(state, world, BOX) and state.x < 76 * S,
		"carry retreats opposite platform motion when pressed into a wall"
	)


func callback_checks() -> void:
	var entity := solid("unit-full", 64 * S, 64 * S)
	var state := player([entity], 64 * S, 84 * S)
	var world := geometry()
	Collision.begin_step(state, world, Shapes)
	state.vy = -12 * S
	Collision.vertical(state, world, BOX, -12 * S)
	check(entity.bump_count == 1 and entity.last_side == 0, "ceiling hit calls below bump once")
	var actor := {"x": 64 * S, "y": 84 * S, "vx": 0, "vy": -12 * S}
	Collision.vertical(actor, world, BOX, -12 * S)
	check(entity.bump_count == 1, "actor geometry does not impersonate a player bump")
	state.frame += 1
	Collision.begin_step(state, world, Shapes)
	state.y = 50 * S
	state.vy = 12 * S
	state.move_action = 2
	entity.break_on_pound = 1
	var moved := Collision.vertical(state, world, BOX, 12 * S)
	check(entity.bump_count == 2 and entity.last_side == 1, "pound calls the upper bump hook")
	check(entity.broken == 1 and moved == 12 * S, "broken solid permits the remaining pound motion")
	var upper := solid("unit-full", 64 * S, 64 * S)
	var lower := solid("unit-full", 64 * S, 80 * S)
	lower.id = "lower"
	upper.shift_player = 16 * S
	state = player([upper, lower], 64 * S, 50 * S)
	state.move_action = 2
	state.vy = 12 * S
	world = geometry()
	Collision.begin_step(state, world, Shapes)
	Collision.vertical(state, world, BOX, 12 * S)
	check(
		upper.bump_count == 1 and lower.bump_count == 0,
		"callback motion cannot add a new contact to the same pound"
	)
	state = player([solid("unit-full", 64 * S, 64 * S)], 64 * S, 64 * S)
	state.move_action = 2
	state.vy = S
	world = geometry()
	Collision.begin_step(state, world, Shapes)
	Collision.vertical(state, world, BOX, S)
	check(state.entities[0].bump_count == 0, "pound hook requires entry from above")


func span_type_checks() -> void:
	check(Registry.implemented("p3"), "cloud span is registered")
	if not Registry.implemented("p3"):
		return
	var world := typed_world({"span": {"A": "p3", "X": 200, "Y": 160, "E1": "96.9"}})
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	check(
		type.solid_box(entity) == [152 * S, 144 * S, 248 * S, 146 * S],
		"span width uses truncated input and raised support line"
	)
	state.x = 200 * S
	state.y = 144 * S - GAP
	state.on_floor = 1
	Sim.advance(state, 0, world)
	check(state.on_floor == 1 and state.y < 144 * S, "real step stands on the typed span")
	var data := Snapshot.encode(state)
	var restored := Snapshot.decode(data, world.identity, world)
	check(restored.ok and Snapshot.encode(restored.state) == data, "typed span snapshot round trip")
	check(
		not (
			World
			. setup_objects(
				{"objects": {"bad": {"A": "p3", "X": 0, "Y": 0, "E1": "wide"}}}, geometry()
			)
			. ok
		),
		"invalid span input is rejected"
	)


func crumble_type_checks() -> void:
	check(Registry.implemented("o20"), "crumbling span is registered")
	if not Registry.implemented("o20"):
		return
	var world := typed_world({"fall": {"A": "o20", "X": 160, "Y": 160, "F": 1}})
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	state.x = 160 * S
	state.y = 144 * S - GAP
	state.on_floor = 1
	Collision.begin_step(state, world, Registry)
	type.contact(entity, state, world, 0)
	check(entity.age == 1, "standing starts a 1.2 second countdown")
	state.x = 220 * S
	type.contact(entity, state, world, 0)
	check(entity.age == 0, "leaving before the fall cancels the countdown")
	state.x = 160 * S
	type.contact(entity, state, world, 0)
	for tick in 72:
		type.step(entity, state, world)
	check(
		entity.age == 73 and entity.y == 160 * S and entity.vy == 256,
		"countdown enables falling with post-motion gravity"
	)
	type.step(entity, state, world)
	check(entity.y == 160 * S + 256, "falling uses fixed-step velocity")
	entity.y = Screen.centre_y(state, world) + 833 * S
	type.step(entity, state, world)
	check(
		entity.y == 160 * S and entity.age == 0 and entity.vy == 0,
		"repeat form resets after falling below the reference region"
	)
	entity.respawns = 0
	entity.age = 73
	entity.y = Screen.centre_y(state, world) + 833 * S
	type.step(entity, state, world)
	check(entity.status == 3, "ordinary crumble is removed below the reference region")
	world = typed_world({"ride": {"A": "o20", "X": 160, "Y": 160}})
	state = _placed_state(world)
	state.entities[0].age = 73
	state.entities[0].vy = 192 * 60
	state.x = 160 * S
	state.y = 144 * S - GAP
	state.on_floor = 1
	var encoded := Snapshot.encode(state)
	var decoded := Snapshot.decode(encoded, world.identity, world)
	check(decoded.ok, "moving support state decodes through the actual codec")
	if decoded.ok:
		for tick in 12:
			Sim.advance(state, 0, world)
			Sim.advance(decoded.state, 0, world)
		check(
			Snapshot.encode(state) == Snapshot.encode(decoded.state),
			"restored moving support has identical first and later ticks"
		)


func block_type_checks() -> void:
	check(Registry.implemented("o28"), "hard block is registered")
	if not Registry.implemented("o28"):
		return
	var world := typed_world({"block": {"A": "o28", "X": 160, "Y": 160, "F": 4}})
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	check(
		type.solid_box(entity) == [128 * S, 128 * S, 192 * S, 192 * S],
		"hard block has full fixed-size volume"
	)
	var projectile := {"bounces": 4}
	check(
		(
			type.projectile_contact(entity, projectile, state, world) == 3
			and entity.form == 5
			and projectile.bounces == 5
		),
		"first strike cracks the selected block form and continues"
	)
	type.projectile_contact(entity, projectile, state, world)
	check(entity.status == 3 and type.solid_box(entity).is_empty(), "second strike removes volume")
	entity.status = 1
	entity.form = 9
	type.hit(entity, state, world, 2, 0)
	check(entity.status == 1, "pound does not invent an unsupported block break")
	type.hit(entity, state, world, 1, 0)
	check(entity.status == 3, "an initially cracked form needs one projectile strike")


func redirect_type_checks() -> void:
	check(Registry.implemented("o19"), "rotating redirector is registered")
	if not Registry.implemented("o19"):
		return
	var world := typed_world(
		{
			"redirect":
			{"A": "o19", "X": 160, "Y": 160, "R": 90, "E1": "-45", "E2": "0.25", "E3": "1"}
		}
	)
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	var projectile := {
		"x": 140 * S,
		"y": 160 * S,
		"vx": 1024 * 60,
		"vy": 0,
		"mode": 1,
		"colour": 1,
		"bounces": 4,
		"fall_on_terrain": 0,
		"camera": 0,
		"despawn_ticks": 0,
		"token": 31
	}
	check(
		type.projectile_contact(entity, projectile, state, world) == 2,
		"redirector continues the projectile"
	)
	check(
		(
			projectile.x == entity.x
			and projectile.y == entity.y
			and projectile.vx == 1024 * 60
			and projectile.vy == 0
		),
		"rightward arrow snaps position and preserves speed"
	)
	check(
		(
			projectile.colour == 1
			and projectile.bounces == 4
			and projectile.fall_on_terrain == 0
			and projectile.camera == 1
		),
		"redirect preserves budget and colour, and enables its camera flag"
	)
	check(
		projectile.despawn_ticks == 600 and entity.status == 1,
		"reusable redirect starts ten-second expiry"
	)
	projectile.despawn_ticks = 400
	type.projectile_contact(entity, projectile, state, world)
	check(
		projectile.despawn_ticks == 400,
		"same projectile does not refresh the same redirector's expiry"
	)
	for tick in 14:
		type.step(entity, state, world)
	check(entity.angle == 90000, "rotation waits for the configured interval")
	type.step(entity, state, world)
	check(
		entity.angle == 45000 and entity.colour >= 0,
		"rotation applies its signed increment at the deadline"
	)
	type.projectile_contact(entity, projectile, state, world)
	check(
		projectile.vx > 0 and projectile.vy < 0,
		"diagonal redirect changes both saved velocity axes"
	)
	var magnitude: int = preload("res://src/sim/enemy_motion.gd").root(
		projectile.vx * projectile.vx + projectile.vy * projectile.vy
	)
	check(
		absi(magnitude - 1024 * 60) <= 2,
		"diagonal redirect retains the speed budget within integer rounding"
	)
	entity.infinite = 0
	type.projectile_contact(entity, projectile, state, world)
	check(entity.status == 3, "ordinary redirector is single-use")
	check(
		not (
			World
			. setup_objects(
				{"objects": {"bad": {"A": "o19", "X": 0, "Y": 0, "R": "left"}}}, geometry()
			)
			. ok
		),
		"invalid redirect angle is rejected"
	)


func gate_type_checks() -> void:
	check(Registry.implemented("o31"), "directional gate is registered")
	if not Registry.implemented("o31"):
		return
	var world := typed_world({"gate": {"A": "o31", "X": 200, "Y": 200}})
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	Collision.begin_step(state, world, Registry)
	state.x = 200 * S
	state.y = 170 * S
	type.step(entity, state, world)
	check(
		entity.opened == 0 and not type.solid_box(entity).is_empty(),
		"gate stays solid on its forbidden side"
	)
	state.y = 260 * S
	type.step(entity, state, world)
	check(
		entity.opened == 1 and type.solid_box(entity).is_empty(),
		"entry sensor opens the allowed side before body collision"
	)
	state.y = 200 * S
	type.step(entity, state, world)
	check(entity.opened == 1, "gate stays open while a body occupies the barrier")
	state.x = 400 * S
	type.step(entity, state, world)
	check(entity.opened == 0, "gate closes after all bodies leave")
	var egg := {"x": 200 * S, "y": 230 * S, "vx": 0, "vy": -1000, "mode": 1}
	check(
		type.projectile_contact(entity, egg, state, world) == 0 and entity.opened == 1,
		"egg can open the allowed entry without being consumed"
	)
	entity.opened = 0
	entity.angle = 45000
	var probe := {"x": 250 * S, "y": 150 * S}
	check(
		not Collision.overlaps(probe, world, [-S, -S, S, S]),
		"rotated AABB's empty corner is not solid"
	)
	probe.x = 200 * S
	probe.y = 200 * S
	check(
		Collision.overlaps(probe, world, [-S, -S, S, S]),
		"rotated barrier retains its central volume"
	)
	world = typed_world({"fractional": {"A": "o31", "X": 200, "Y": 200, "R": 103.125}})
	state = _placed_state(world)
	entity = state.entities[0]
	Collision.begin_step(state, world, Registry)
	probe.x = 229 * S
	probe.y = 139 * S
	check(
		entity.angle == 103125 and not Collision.overlaps(probe, world, [-S, -S, S, S]),
		"fractional rotation uses saved integer corners and narrow phase"
	)
	var encoded := Snapshot.encode(state)
	var restored := Snapshot.decode(encoded, world.identity, world)
	check(
		restored.ok and Snapshot.encode(restored.state) == encoded,
		"rotated gate saves without transient geometry facts"
	)
	world = typed_world(
		{"gate": {"A": "o31", "X": 200, "Y": 200}, "walker": {"A": "e1", "X": 200, "Y": 230}}
	)
	state = _placed_state(world)
	state.x = 400 * S
	state.entities[1].status = 1
	Collision.begin_step(state, world, Registry)
	type.step(state.entities[0], state, world)
	check(state.entities[0].opened == 1, "terrain-aware actor can open the entry sensor")
	state.entities[1].status = 3
	type.step(state.entities[0], state, world)
	check(state.entities[0].opened == 0, "defeated actor no longer holds the gate open")


func post_type_checks() -> void:
	check(Registry.implemented("o23"), "pound-driven post is registered")
	if not Registry.implemented("o23"):
		return
	var world := typed_world({"post": {"A": "o23", "X": 160, "Y": 224, "E1": "96", "E2": "9"}})
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	check(
		type.solid_box(entity) == [144 * S, 128 * S, 176 * S, 224 * S],
		"post is bottom anchored with the configured height"
	)
	state.x = 160 * S
	state.y = 124 * S
	state.vy = 2 * Sim.GRAVITY * 60
	state.move_action = 2
	Sim.advance(state, 32, world)
	check(
		entity.height == 64 * S and state.y == 160 * S - GAP,
		"real pound drives the post and rider down by 32 pixels"
	)
	check(state.move_action == 3 and state.on_floor == 1, "driving completes one pound landing")
	Sim.advance(state, 32, world)
	check(entity.height == 64 * S, "holding down does not drive the post twice")
	Collision.begin_step(state, world, Registry)
	type.bump(entity, state, world, 0)
	check(entity.height == 64 * S, "ordinary underside contact does not drive a post")
	type.bump(entity, state, world, 1)
	type.bump(entity, state, world, 1)
	check(
		entity.status == 3 and type.solid_box(entity).is_empty(),
		"last drive removes the collision volume"
	)
	check(
		type.view_state(entity, state).size_y == 16, "last drive retains the non-solid stump view"
	)
	world = typed_world(
		{"spiked": {"A": "o23", "X": 160, "Y": 224, "E1": "96", "E2": "16", "E3": "1"}}
	)
	state = _placed_state(world)
	entity = state.entities[0]
	state.x = 160 * S
	state.y = 128 * S - GAP
	Collision.begin_step(state, world, Registry)
	type.contact(entity, state, world, 0)
	check(
		state.invulnerable == 120 and state.separated == 1,
		"spiked form uses the shared damage and companion path"
	)
	type.bump(entity, state, world, 1)
	check(entity.height == 96 * S, "spiked form cannot be driven")


func cache_type_checks() -> void:
	check(Registry.implemented("o8"), "floating release cache is registered")
	if not Registry.implemented("o8"):
		return
	var world := typed_world(
		{"cache": {"A": "o8", "X": 200, "Y": 160, "E1": "1", "E2": "5", "E3": "1", "F": 9}}
	)
	# Wide enough that the map-clamped screen can leave the cache.
	world.width = 4096 * S
	world.maps[1].width = world.width
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	Collision.begin_step(state, world, Registry)
	check(
		not type.view_state(entity, state).visible,
		"hidden cache starts invisible independently of preview frame"
	)
	var projectile := {"mode": 1}
	check(
		type.projectile_contact(entity, projectile, state, world) == 1 and entity.phase == 2,
		"first egg is consumed to reveal a hidden cache"
	)
	check(type.view_state(entity, state).modulate_alpha == 0.5, "temporary reveal has half opacity")
	state.camera_x = 1000 * S
	type.step(entity, state, world)
	check(entity.phase == 0, "temporary reveal ends when the cache leaves the fixed reference area")
	state.camera_x = 200 * S
	state.x = entity.x
	state.y = entity.y
	type.contact(entity, state, world, 0)
	check(entity.phase == 2, "body overlap reveals but does not open")
	check(
		type.tongue(entity, state, world) == 0 and entity.phase == 2,
		"tongue cannot swallow or open a cache"
	)
	type.hit(entity, state, world, 2, 0)
	check(entity.phase == 2, "ordinary pound is not a release strike")
	type.projectile_contact(entity, projectile, state, world)
	check(entity.phase == 3 and entity.age == 0, "next egg begins opening a revealed cache")
	for tick in 18:
		type.step(entity, state, world)
	check(
		type.view_state(entity, state).size_x == 48.0 and entity.status == 1,
		"growth ends at 0.30 seconds before the release animation"
	)
	var encoded := Snapshot.encode(state)
	var decoded := Snapshot.decode(encoded, world.identity, world)
	check(decoded.ok, "opening cache snapshot uses only declared fields")
	for tick in 12:
		type.step(entity, state, world)
	check(entity.status == 3, "release waits for the half-second animation")
	if Registry.implemented("o1"):
		check(
			entity.release_failures == 0 and entity.collected == 1 and state.entities.size() == 6,
			"shared spawner releases every configured coin"
		)
		for drop: Dictionary in state.entities.slice(1):
			check(
				(
					drop.code == "o1"
					and drop.moving == 1
					and drop.despawn_ticks == 480
					and drop.vy >= -768 * 60
					and drop.vy <= -512 * 60
				),
				"released coin has the configured motion and eight-second lifetime"
			)
		var released := Snapshot.encode(state)
		var release_restore := Snapshot.decode(released, world.identity, world)
		check(
			release_restore.ok and Snapshot.encode(release_restore.state) == released,
			"released dynamic contents round trip with the originating cache"
		)
	else:
		check(
			entity.release_failures == 5 and entity.collected == 0 and state.entities.size() == 1,
			"missing shared spawner is explicit and cannot award phantom pickups"
		)
	world = typed_world({"bob": {"A": "o8", "X": 200, "Y": 160}})
	state = State.create(world)
	entity = state.entities[0]
	check(entity.age == 152, "a placed cache starts with the wave the level intro has run")
	entity.age = 0
	Collision.begin_step(state, world, Registry)
	for tick in 45:
		type.step(entity, state, world)
	check(entity.y == 176 * S, "floating cache follows its saved three-second 16-pixel wave")
	var first: Dictionary = type.view_state(entity, state)
	var second: Dictionary = type.view_state(entity, state)
	check(first == second, "cache drawing policy is pure")
	for content in [2, 3, 4]:
		world = typed_world(
			{"release": {"A": "o8", "X": 200, "Y": 160, "E1": str(content), "E2": "3"}}
		)
		state = _placed_state(world)
		entity = state.entities[0]
		entity.phase = 3
		entity.age = 29
		state.health = 29
		Collision.begin_step(state, world, Registry)
		type.step(entity, state, world)
		if not Registry.implemented("o1"):
			check(
				entity.release_failures == (3 if content == 2 else 1),
				"unavailable release providers remain explicit"
			)
			continue
		check(entity.release_failures == 0, "all release families use declared runtime options")
		if content == 2:
			check(
				(
					state.entities.size() == 4
					and state.entities[1].code == "o4"
					and state.entities[2].code == "o1"
					and state.entities[3].code == "o1"
				),
				"health drops stop at thirty and excess contents become coins"
			)
		elif content == 3:
			var flower: Dictionary = state.entities[1]
			check(
				(
					flower.code == "o3"
					and flower.origin_token == entity.token
					and entity.collected == 0
				),
				"released flower retains its originating cache token"
			)
			Registry.lookup("o3").collect(flower, state)
			check(entity.collected == 1, "collecting the flower marks its original cache")
		else:
			check(
				(
					state.entities.size() == 2
					and state.entities[1].code == "o14"
					and state.entities[1].source_index == -1
				),
				"switch contents use the dynamic switch type"
			)


func switch_type_checks() -> void:
	check(Registry.implemented("o14"), "timed switch is registered")
	if not Registry.implemented("o14"):
		return
	var world := typed_world(
		{
			"switch": {"A": "o14", "X": 200, "Y": 200, "F": 1},
			"fall": {"A": "o20", "X": 500, "Y": 500}
		}
	)
	var state := _placed_state(world)
	var entity: Dictionary = state.entities[0]
	var type := Registry.lookup(entity.code)
	entity.status = 1
	state.entities[1].age = 1
	state.x = 200 * S
	state.y = 180 * S
	state.vy = 10 * S
	state.invulnerable = 60
	Collision.begin_step(state, world, Registry)
	type.contact(entity, state, world, 0)
	check(
		state.modal_token == entity.token and entity.phase == 1,
		"falling contact starts the switch-owned modal"
	)
	for tick in 9:
		Sim.advance(state, 0, world)
	check(
		state.y > 196 * S and state.y < 198 * S,
		"flatten follows the outward sine curve rather than a linear offset"
	)
	for tick in 9:
		Sim.advance(state, 0, world)
	check(
		state.y == 204 * S and entity.phase == 2,
		"flatten lasts 18 ticks and offsets the player by 24 pixels"
	)
	check(
		state.entities[1].age == 1 and state.invulnerable == 60,
		"modal freezes other objects and lifetime counters"
	)
	check(
		state.switch_sound_serial == 1 and state.switch_sound_kind == 1,
		"flatten completion emits the activation sound marker"
	)
	var encoded := Snapshot.encode(state)
	var decoded := Snapshot.decode(encoded, world.identity, world)
	check(decoded.ok, "switch modal snapshot is fully declared")
	for tick in 9:
		Sim.advance(state, 4, world)
		if tick == 2:
			check(
				state.y > 200 * S and state.y < 202 * S,
				"unflatten begins with the inward sine curve"
			)
		if decoded.ok:
			Sim.advance(decoded.state, 4, world)
	check(
		state.modal_token == 0 and state.y == 180 * S and state.vy == -1008 * 60,
		"unflatten takes nine ticks and held jump selects the high launch"
	)
	check(
		state.switch_ticks == 630 and entity.phase == 3,
		"completion starts a shared ten-and-a-half-second timer"
	)
	if decoded.ok:
		check(
			Snapshot.encode(state) == Snapshot.encode(decoded.state),
			"resuming the modal produces identical launch and timer state"
		)
	for tick in 630:
		state.frame += 1
		Collision.begin_step(state, world, Registry)
		type.step(entity, state, world)
	check(
		state.switch_ticks == 0 and entity.phase == 0 and entity.y == 200 * S,
		"repeat switch returns at shared timer expiry"
	)
	state.switch_ticks = 300
	state.y = 180 * S
	state.vy = 10 * S
	type.contact(entity, state, world, 0)
	for tick in 27:
		Sim.advance(state, 0, world)
	check(
		state.switch_ticks == 630 and state.vy == -448 * 60,
		"another press resets the running timer and uses the ordinary launch"
	)
	world = typed_world(
		{"first": {"A": "o14", "X": 200, "Y": 200}, "second": {"A": "o14", "X": 300, "Y": 200}}
	)
	state = _placed_state(world)
	state.switch_ticks = 100
	for trigger: Dictionary in state.entities:
		trigger.status = 1
	Collision.begin_step(state, world, Registry)
	for trigger: Dictionary in state.entities:
		type.step(trigger, state, world)
	check(state.switch_ticks == 99, "multiple switches advance one shared timer only once")
	state.entities[0].phase = 3
	state.entities[0].y += 16 * S
	state.switch_ticks = 1
	type.step(state.entities[0], state, world)
	check(
		state.entities[0].status == 3, "ordinary hidden switch is retired after carrying the timer"
	)


func shared_interaction_checks() -> void:
	if Registry.implemented("o15"):
		var world := typed_world(
			{
				"trigger": {"A": "o14", "X": 200, "Y": 200, "F": 1},
				"linked": {"A": "o15", "X": 400, "Y": 200},
				"coin": {"A": "o1", "X": 300, "Y": 200, "F": 1}
			}
		)
		var state := _placed_state(world)
		var trigger: Dictionary = state.entities[0]
		trigger.status = 1
		state.x = 200 * S
		state.y = 180 * S
		state.vy = 10 * S
		Registry.lookup("o14").contact(trigger, state, world, 0)
		for tick in 27:
			Sim.advance(state, 0, world)
		check(
			state.entities[1].enabled == 1 and state.entities[2].enabled == 1,
			"switch activation reaches linked blocks and dotted coins"
		)
		state.switch_ticks = 1
		Sim.advance(state, 0, world)
		check(
			state.entities[1].enabled == 0 and state.entities[2].enabled == 0,
			"shared timer expiry flips linked objects back"
		)
	if not Registry.implemented("o7"):
		return
	var world := typed_world({"rock": {"A": "o28", "X": 200, "Y": 200}})
	var state := _placed_state(world)
	state.x = 20 * S
	state.y = 20 * S
	var egg := Registry.spawn_dynamic(
		state,
		world,
		"o7",
		145 * S,
		200 * S,
		{"mode": 1, "vx": 1024 * 60, "vy": 0, "bounces": 4, "colour": 0}
	)
	check(not egg.is_empty(), "shared projectile type permits runtime creation")
	if egg.is_empty():
		return
	Sim.advance(state, 0, world)
	check(
		state.entities[0].form == 1 and egg.bounces == 4 and egg.colour == 1 and egg.vx < 0,
		"first real projectile strike cracks and bounces without spending its budget"
	)
	egg = Registry.spawn_dynamic(
		state,
		world,
		"o7",
		145 * S,
		200 * S,
		{"mode": 1, "vx": 1024 * 60, "vy": 0, "bounces": 4, "colour": 0}
	)
	Sim.advance(state, 0, world)
	check(
		state.entities[0].status == 3 and egg.bounces == 4 and egg.colour == 1 and egg.vx < 0,
		"final real projectile strike retains its pre-destruction bounce and colour change"
	)
	world = typed_world({"arrow": {"A": "o19", "X": 200, "Y": 200, "R": 0, "E3": "1"}})
	state = _placed_state(world)
	state.x = 20 * S
	state.y = 20 * S
	egg = Registry.spawn_dynamic(
		state,
		world,
		"o7",
		170 * S,
		200 * S,
		{"mode": 1, "vx": 1024 * 60, "vy": 0, "bounces": 4, "colour": 0}
	)
	Sim.advance(state, 0, world)
	check(
		egg.vx == 0 and egg.vy < 0 and egg.colour == 0 and egg.bounces == 4 and egg.camera == 1,
		"real projectile dispatch retains redirect velocity, budget, colour and camera"
	)
	check(
		egg.x == 200 * S and egg.y == 200 * S,
		"redirect ends its hit tick snapped to the cloud before next-tick motion"
	)


func typed_world(objects: Dictionary) -> Dictionary:
	var world := geometry()
	world.identity = "synthetic platform state".sha256_text()
	world.spawn_x = 64 * S
	world.spawn_y = 100 * S
	world.spawn_facing = 1
	world.map_index = 1
	world.initial_map = 1
	world.map_count = 1
	world.flowers_target = 0
	world.redcoins_target = 0
	check(World.setup_objects({"objects": objects}, world).ok, "typed synthetic placements compile")
	world.maps = {1: world.duplicate()}
	return world


static func geometry() -> Dictionary:
	return {"layers": [], "bridges": [], "width": 1024 * S, "height": 1024 * S}


static func solid(code: String, x: int, y: int) -> Dictionary:
	return {
		"code": code,
		"id": "shape",
		"status": 1,
		"x": x,
		"y": y,
		"vx": 0,
		"vy": 0,
		"bump_count": 0,
		"last_side": -1,
		"broken": 0
	}


static func player(entities: Array, x: int, y: int) -> Dictionary:
	return {
		"x": x,
		"y": y,
		"vx": 0,
		"vy": 0,
		"on_floor": 0,
		"move_action": 0,
		"frame": 1,
		"entities": entities
	}


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


## Entities run one world tick at level start, as in the original. These unit checks
## start from the placement, so the table is spawned again after the level start.
func _placed_state(world: Dictionary) -> Dictionary:
	var state := State.create(world)
	Registry.spawn_map(state, world)
	return state
