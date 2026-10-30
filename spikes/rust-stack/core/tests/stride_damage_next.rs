//! Next vertical admission gate. It is intentionally not admitted by the current slice.
use eggshell_spike_core::{schema::Schema, wire::WireSnapshot, Session};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "next milestone: implement actual damage/separation/rescue before admitting this route"]
fn stride_damage_original_every_tick_parity() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_DAMAGE_DIR").unwrap());
    let level = fs::read_to_string(project.join("tests/fixtures/stride.level.json")).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    let inputs: Vec<u8> = serde_json::from_slice(
        &fs::read(project.join("tests/fixtures/stride.damage.input.json")).unwrap(),
    )
    .unwrap();
    let stream = fs::read(root.join("snapshots.v10.stream")).unwrap();
    let mut cursor = 0;
    for tick in 0..=inputs.len() {
        let size = u32::from_le_bytes(stream[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4;
        let expected = &stream[cursor..cursor + size];
        cursor += size;
        let actual = session.snapshot().unwrap();
        if actual != expected {
            let identity = expected[12..44].try_into().unwrap();
            let a = WireSnapshot::decode(expected, identity, &schema).unwrap();
            let b = WireSnapshot::decode(&actual, identity, &schema).unwrap();
            panic!(
                "damage mismatch tick={tick} {:?}",
                a.first_difference(&b, &schema)
            );
        }
        if tick < inputs.len() {
            session.advance(inputs[tick]).unwrap_or_else(|error| {
                panic!("next vertical gate rejected tick={}: {error}", tick + 1)
            });
        }
    }
    println!("STRIDE_DAMAGE_DONE snapshots={}", inputs.len() + 1);
}
