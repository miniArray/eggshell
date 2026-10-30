use eggshell_spike_core::{math, polygon, Position, World};
use serde_json::Value;
use std::{fs, path::PathBuf};
fn root() -> PathBuf {
    PathBuf::from(std::env::var("CORE_PROOF_DIR").expect("private proof directory"))
}
fn integer(v: &Value) -> i64 {
    v.as_i64().unwrap()
}
#[test]
#[ignore = "requires freshly exported private Godot oracle"]
fn original_godot_integer_rng_screen_and_polygon_results_match() {
    let value: Value =
        serde_json::from_slice(&fs::read(root().join("primitives.json")).unwrap()).unwrap();
    let mut rng = math::Rng::from_saved(1).unwrap();
    for row in value["rng"].as_array().unwrap() {
        assert_eq!(
            [
                rng.ticks(-192 * 60, 192 * 60),
                rng.cycles(),
                rng.ticks(60, 150),
                rng.saved()
            ],
            row.as_array()
                .unwrap()
                .iter()
                .map(integer)
                .collect::<Vec<_>>()
                .as_slice()
        );
    }
    for row in value["sine"].as_array().unwrap() {
        assert_eq!(
            math::sine(integer(&row[0]), integer(&row[1]), integer(&row[2])).unwrap(),
            integer(&row[3])
        );
    }
    for row in value["round"].as_array().unwrap() {
        assert_eq!(
            math::round_units(row[0].as_f64().unwrap()).unwrap(),
            integer(&row[1])
        );
    }
    for row in value["floor_div"].as_array().unwrap() {
        assert_eq!(
            math::floor_div(integer(&row[0]), integer(&row[1])).unwrap(),
            integer(&row[2])
        );
    }
    for row in value["screen"].as_array().unwrap() {
        let actual = math::screen_centre(
            Position {
                x: integer(&row[0]),
                y: integer(&row[1]),
            },
            integer(&row[2]),
            integer(&row[3]),
        );
        assert_eq!(
            actual,
            Position {
                x: integer(&row[4]),
                y: integer(&row[5])
            }
        );
    }
    for row in value["polygon"].as_array().unwrap() {
        let flat = row[0].as_array().unwrap();
        let points = flat
            .as_chunks::<2>()
            .0
            .iter()
            .map(|p| Position {
                x: integer(&p[0]),
                y: integer(&p[1]),
            })
            .collect::<Vec<_>>();
        let bounds = std::array::from_fn(|i| integer(&row[1][i]));
        assert_eq!(
            polygon::overlaps_box(&points, bounds),
            row[2].as_bool().unwrap()
        );
    }
    println!("PRIMITIVE_RUST_DONE rng=512 sine=2001 polygon=441");
}
#[test]
#[ignore = "requires freshly exported private target world oracle"]
fn unchanged_target_placements_terrain_transforms_and_contacts_match() {
    let level = fs::read_to_string(
        PathBuf::from(std::env::var("HOME").unwrap())
            .join(".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"),
    )
    .unwrap();
    let collision = fs::read_to_string(
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../src/level/collision_table.json"),
    )
    .unwrap();
    let actual = World::compile(&level, &collision).unwrap();
    let value: Value =
        serde_json::from_slice(&fs::read(root().join("world.json")).unwrap()).unwrap();
    assert_eq!(actual.initial_map, integer(&value["initial_map"]) as usize);
    assert_eq!(
        actual.spawn,
        Position {
            x: integer(&value["spawn_x"]),
            y: integer(&value["spawn_y"])
        }
    );
    assert_eq!(actual.maps.len(), value["maps"].as_array().unwrap().len());
    let mut probes = 0;
    for (map, expected) in actual.maps.iter().zip(value["maps"].as_array().unwrap()) {
        assert_eq!(map.width_pixels, integer(&expected["width_pixels"]));
        assert_eq!(map.height_pixels, integer(&expected["height_pixels"]));
        assert_eq!(map.placements.len(), 204);
        let bridges = expected["bridges"].as_array().unwrap();
        assert_eq!(map.bridges.len(), bridges.len());
        for (actual, expected) in map.bridges.iter().zip(bridges) {
            assert_eq!(
                [actual.left, actual.right, actual.top],
                [
                    integer(&expected["left"]),
                    integer(&expected["right"]),
                    integer(&expected["top"])
                ]
            );
        }
        let linked: Vec<usize> = map
            .placements
            .iter()
            .filter_map(|p| match p.prepared {
                eggshell_spike_core::PreparedPlacement::Bridge { geometry_index } => {
                    Some(geometry_index)
                }
                _ => None,
            })
            .collect();
        assert_eq!(linked, (0..map.bridges.len()).collect::<Vec<_>>());
        println!("PREPARED_BRIDGES_DONE map={} immutable_bridges={} zero_based_placement_order=true units=1/3600px",map.name,map.bridges.len());
        for (p, e) in map
            .placements
            .iter()
            .zip(expected["placements"].as_array().unwrap())
        {
            assert_eq!(p.id, e["id"].as_str().unwrap());
            assert_eq!(p.code, e["code"].as_str().unwrap());
            assert_eq!(
                [
                    p.position.x,
                    p.position.y,
                    p.variant,
                    p.mirror,
                    p.rotation,
                    p.layer
                ],
                [
                    integer(&e["x"]),
                    integer(&e["y"]),
                    integer(&e["variant"]),
                    integer(&e["mirror"]),
                    integer(&e["rotation"]),
                    integer(&e["layer"])
                ],
                "placement {}",
                p.id
            );
        }
        assert_eq!(
            map.layers.len(),
            expected["layers"].as_array().unwrap().len()
        );
        for (layer, e) in map
            .layers
            .iter()
            .zip(expected["layers"].as_array().unwrap())
        {
            assert_eq!(layer.tilemap, e["tilemap"].as_str().unwrap());
            assert_eq!(layer.source_layer, e["source_layer"].as_str().unwrap());
            assert_eq!(
                [layer.draw_slot.layer_index, layer.draw_slot.z_order],
                [integer(&e["slot"][0]), integer(&e["slot"][1])]
            );
            assert_eq!(layer.solid, e["solid"].as_bool().unwrap());
            assert_eq!(layer.water, e["water"].as_bool().unwrap());
            assert_eq!(layer.tile_size_pixels, integer(&e["tile_size_pixels"]));
            assert_eq!(
                layer.cells,
                e["cells"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|v| integer(v) as i32)
                    .collect::<Vec<_>>()
            );
            assert_eq!(layer.collision.len(), e["shapes"].as_array().unwrap().len());
            for shape in e["shapes"].as_array().unwrap() {
                let polygon = &layer
                    .collision
                    .iter()
                    .find(|c| c.cell == integer(&shape[0]) as i32)
                    .unwrap()
                    .polygon;
                let flat = polygon.iter().flat_map(|p| [p.x, p.y]).collect::<Vec<_>>();
                assert_eq!(
                    flat,
                    shape[1]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(integer)
                        .collect::<Vec<_>>()
                );
            }
        }
        for probe in expected["probes"].as_array().unwrap() {
            let bounds = std::array::from_fn(|i| integer(&probe[0][i]));
            assert_eq!(
                map.terrain_overlaps(bounds),
                probe[1].as_bool().unwrap(),
                "terrain {bounds:?}"
            );
            assert_eq!(
                map.border_overlaps(bounds),
                probe[2].as_bool().unwrap(),
                "border {bounds:?}"
            );
            probes += 1;
        }
    }
    println!("WORLD_RUST_DONE placements=204 probes={probes}");
}
