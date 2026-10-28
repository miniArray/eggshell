extends SceneTree
## Every lava tilemap is deadly to the player, enemies, stars and eggs.
## Invented levels and the repository collision table only; no scenes or assets.

const Table = preload("res://src/level/collision_table.gd")
const World = preload("res://src/sim/world.gd")
const State = preload("res://src/sim/play_state.gd")
const Registry = preload("res://src/sim/registry.gd")
const Life = preload("res://src/sim/life.gd")
const Body = preload("res://src/sim/enemy_body.gd")
const Egg = preload("res://src/sim/types/item_egg.gd")
const S := preload("res://src/sim/units.gd").SCALE
const FAMILY := ["lava", "lava_1", "lava_2", "lava_3", "lava_4"]
var checks := 0
var failures := 0


func _initialize() -> void:
	check(World.LAVA_LAYERS == FAMILY, "One shared list names all five lava tilemaps")
	var table := Table.read()
	for name: String in FAMILY:
		check(table.tilemaps.has(name), "Collision table has " + name)
		family_checks(name, table)
	print("LAVA_FAMILY_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func family_checks(name: String, table: Dictionary) -> void:
	var built := World.build(JSON.stringify(level(name)), table)
	check(built.ok, name + " level builds")
	if not built.ok:
		return
	var world: Dictionary = built.world
	check(
		World.lava_overlaps(world, 100 * S, 185 * S, 110 * S, 190 * S),
		name + " counts as lava inside its tile shape"
	)
	check(
		not World.lava_overlaps(world, 100 * S, 162 * S, 110 * S, 170 * S),
		name + " is not lava above its tile shape"
	)
	var state := State.create(world)
	state.x = 100 * S
	state.y = 120 * S
	Life.after_step(state, world)
	check(state.life_phase == Life.PLAY, name + ": player above the surface lives")
	state.y = 190 * S
	Life.after_step(state, world)
	check(
		state.life_phase == Life.DEAD and state.death_cause == Life.HAZARD,
		name + " kills the player"
	)
	state = State.create(world)
	var walker := by_code(state, "e4")
	walker.status = 1
	var walker_type: Script = Registry.lookup("e4")
	check(
		Body.hazards(walker, state, world, walker_type.bounds(walker)) and walker.status == 3,
		name + " removes an enemy"
	)
	var star := by_code(state, "o4")
	star.status = 1
	Registry.lookup("o4").step(star, state, world)
	check(star.status == 3, name + " removes a star")
	var egg := by_code(state, "o7")
	check(Egg.liquid_at(world, egg) == 2, name + " is lava to an egg")


static func by_code(state: Dictionary, code: String) -> Dictionary:
	for entity: Dictionary in state.entities:
		if entity.code == code:
			return entity
	return {}


static func level(name: String) -> Dictionary:
	# Ten by six cells of 32 px; the bottom row holds the family's first tile.
	var tilemap := {"c2tilemap": true, "width": 10, "height": 6, "data": "50x-1,10x0"}
	return {
		"version": "s3.13.1",
		"name": "Hot floor",
		"desc": "Synthetic lava row",
		"author": "Eggshell",
		"flowers": 0,
		"redcoins": 0,
		"startpoint": {"map": 1, "X": 32, "Y": 96},
		"maps":
		{
			"map1":
			{
				"width": 320,
				"height": 192,
				"layer1": {name: JSON.stringify(tilemap)},
				"objects":
				{
					"walker": {"A": "e4", "X": 100, "Y": 186},
					"star": {"A": "o4", "X": 160, "Y": 186},
					"egg": {"A": "o7", "X": 220, "Y": 186}
				}
			}
		}
	}


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
