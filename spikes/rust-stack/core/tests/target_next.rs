//! Selected unchanged 204-placement target. This is a red gate until runtime closure exists.
use eggshell_spike_core::{schema::Schema, wire::WireSnapshot, Session, World};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "requires private original target traces on aka"]
fn target_has_uninterrupted_every_tick_parity() {
    let home = PathBuf::from(std::env::var("HOME").unwrap());
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let artifacts = home.join("eggshell-remote/artifacts/full-rust-ab/core");
    let root = std::env::var("CORE_TARGET_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| artifacts.join("target-4.7.2"));
    let input = std::env::var("CORE_TARGET_INPUT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| artifacts.join("target.input.json"));
    let level = fs::read_to_string(
        home.join(".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"),
    )
    .unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let world = World::compile(&level, &collision).unwrap();
    assert_eq!(
        world.maps.iter().map(|m| m.placements.len()).sum::<usize>(),
        204
    );
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let inputs: Vec<u8> = serde_json::from_slice(&fs::read(input).unwrap()).unwrap();
    let stream = fs::read(root.join("snapshots.v10.stream")).unwrap();
    let mut session = Session::load(&level, &collision, &metadata)
        .unwrap_or_else(|e| panic!("target204 next runtime gate at initialization: {e}"));
    let mut cursor = 0;
    for tick in 0..=inputs.len() {
        let size = u32::from_le_bytes(stream[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4;
        let expected = &stream[cursor..cursor + size];
        cursor += size;
        let actual = session.snapshot().unwrap();
        if actual != expected {
            let a = WireSnapshot::decode(expected, world.identity, &schema).unwrap();
            let b = WireSnapshot::decode(&actual, world.identity, &schema).unwrap();
            panic!(
                "target204 mismatch tick={tick}: {:?}",
                a.first_difference(&b, &schema)
            );
        }
        if tick < inputs.len() {
            session
                .advance(inputs[tick])
                .unwrap_or_else(|e| panic!("target204 next runtime gate tick={}: {e}", tick + 1));
        }
    }
    assert_eq!(session.stats().completed_ticks, inputs.len() as u64);
    assert_eq!(session.stats().restore_count, 0);
    println!("TARGET204_UNINTERRUPTED_DONE snapshots={} accepted_ticks={} saved_frame={} coverage_route_is_not_assumed_complete=true",inputs.len()+1,session.stats().completed_ticks,session.stats().tick);
}
