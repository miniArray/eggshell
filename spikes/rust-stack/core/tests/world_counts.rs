//! Source collectible goals are immutable compiler facts, not placement counts.
use eggshell_spike_core::World;
use std::{fs, path::PathBuf};
fn project() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
fn data() -> (serde_json::Value, String) {
    (
        serde_json::from_str(
            &fs::read_to_string(project().join("tests/fixtures/stride.level.json")).unwrap(),
        )
        .unwrap(),
        fs::read_to_string(project().join("data/collision_table.json")).unwrap(),
    )
}
#[test]
fn negative_and_absent_source_goals_default_to_zero_without_counting_placements() {
    let (mut level, collision) = data();
    level.as_object_mut().unwrap().remove("flowers");
    level["redcoins"] = (-5).into();
    let world = World::compile(&level.to_string(), &collision).unwrap();
    assert_eq!((world.flowers_target, world.redcoins_target), (0, 0));
    level["flowers"] = 3.into();
    level["redcoins"] = 7.into();
    let world = World::compile(&level.to_string(), &collision).unwrap();
    assert_eq!((world.flowers_target, world.redcoins_target), (3, 7));
}
#[test]
#[ignore = "requires original Godot source conversion/refusal cases"]
fn original_world_count_conversion_and_refusal_match() {
    let (source, collision) = data();
    let root = PathBuf::from(std::env::var("CORE_PROOF_DIR").unwrap());
    let cases: Vec<serde_json::Value> =
        serde_json::from_slice(&fs::read(root.join("world-counts.json")).unwrap()).unwrap();
    for case in &cases {
        let mut level = source.clone();
        for (index, field) in ["flowers", "redcoins"].iter().enumerate() {
            let value = &case["input"][index];
            if value.is_null() {
                level.as_object_mut().unwrap().remove(*field);
            } else {
                level[*field] = value.clone();
            }
        }
        let compiled = World::compile(&level.to_string(), &collision);
        assert_eq!(
            compiled.is_ok(),
            case["ok"].as_bool().unwrap(),
            "case={case}"
        );
        if let Ok(world) = compiled {
            assert_eq!(
                world.flowers_target,
                case["flowers_target"].as_i64().unwrap()
            );
            assert_eq!(
                world.redcoins_target,
                case["redcoins_target"].as_i64().unwrap()
            );
        }
    }
    println!(
        "WORLD_COUNTS_RUST_DONE cases={} placement_count_inference=false",
        cases.len()
    );
}
