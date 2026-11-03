//! Immutable prepared facts; these are not gameplay admission or benchmark evidence.
use eggshell_spike_core::{
    BridgeGeometry, Error, PreparedPlacement, PropertyValue, Session, World, SCALE as S,
};
use std::{fs, path::PathBuf};
fn project() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
fn collision() -> String {
    fs::read_to_string(project().join("data/collision_table.json")).unwrap()
}
#[test]
fn bounce_preparation_keeps_one_ordered_integer_bridge_owner() {
    let level = fs::read_to_string(project().join("tests/fixtures/bounce.level.json")).unwrap();
    let world = World::compile(&level, &collision()).unwrap();
    let map = &world.maps[0];
    assert_eq!(
        map.bridges,
        [BridgeGeometry {
            left: 864 * S,
            right: 1056 * S,
            top: 256 * S
        }]
    );
    let bridge = map.placements.iter().find(|p| p.code == "p1").unwrap();
    assert_eq!(
        bridge.prepared,
        PreparedPlacement::Bridge { geometry_index: 0 }
    );
    assert_eq!(bridge.position.y, 272 * S);
    assert_eq!(
        bridge
            .properties
            .iter()
            .find(|(key, _)| key == "E1")
            .unwrap()
            .1,
        PropertyValue::String("192".into())
    );
    let pad = map.placements.iter().find(|p| p.code == "o11").unwrap();
    assert_eq!(pad.position.y, 384 * S);
    assert_eq!(
        pad.prepared,
        PreparedPlacement::Pad {
            large: false,
            single_use: false
        }
    );
    assert_eq!(
        pad.properties.iter().find(|(key, _)| key == "Y").unwrap().1,
        PropertyValue::Number(368.0)
    );
}
#[test]
fn pad_variants_are_source_flags_not_saved_dynamic_state() {
    let source = fs::read_to_string(project().join("tests/fixtures/bounce.level.json")).unwrap();
    let mut value: serde_json::Value = serde_json::from_str(&source).unwrap();
    for form in 0..4 {
        value["maps"]["map1"]["objects"]["pad"]["F"] = form.into();
        let world = World::compile(&value.to_string(), &collision()).unwrap();
        let pad = world.maps[0]
            .placements
            .iter()
            .find(|p| p.code == "o11")
            .unwrap();
        assert_eq!(
            pad.prepared,
            PreparedPlacement::Pad {
                large: form % 2 != 0,
                single_use: form >= 2
            }
        );
    }
    value["maps"]["map1"]["objects"]["pad"]["F"] = 4.into();
    assert!(matches!(
        World::compile(&value.to_string(), &collision()),
        Err(Error::Unsupported { .. })
    ));
}
#[test]
fn bridge_uses_rounded_integer_width_before_halving() {
    let source = fs::read_to_string(project().join("tests/fixtures/bounce.level.json")).unwrap();
    let mut value: serde_json::Value = serde_json::from_str(&source).unwrap();
    value["maps"]["map1"]["objects"]["bridge"]["E1"] = "0.00083333333333333333".into();
    let world = World::compile(&value.to_string(), &collision()).unwrap();
    assert_eq!(
        world.maps[0].bridges,
        [BridgeGeometry {
            left: 960 * S - 1,
            right: 960 * S + 1,
            top: 256 * S
        }]
    );
    value["maps"]["map1"]["objects"]["bridge"]["E1"] = "-1".into();
    assert!(World::compile(&value.to_string(), &collision()).is_err());
}
#[test]
#[ignore = "requires original Godot schema; immutable preparation must not waive admission"]
fn none_preparation_does_not_waive_unknown_gameplay_admission() {
    let root = PathBuf::from(std::env::var("CORE_ORACLE_DIR").unwrap());
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let level = fs::read_to_string(project().join("tests/fixtures/bounce.level.json")).unwrap();
    let mut value: serde_json::Value = serde_json::from_str(&level).unwrap();
    value["maps"]["map1"]["objects"]["goal"]["A"] = "unsupported_verification_type".into();
    let code = value.to_string();
    let world = World::compile(&code, &collision()).unwrap();
    assert_eq!(
        world.maps[0].placements[0].prepared,
        PreparedPlacement::None
    );
    assert!(matches!(
        Session::load(&code, &collision(), &metadata),
        Err(Error::Unsupported { .. })
    ));
}
