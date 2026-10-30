use eggshell_spike_core::{schema::Schema, wire::WireSnapshot, Session};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "requires original Godot Stride every-tick trace"]
fn uninterrupted_rust_ticks_match_without_oracle_state_injection() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_ORACLE_DIR").unwrap());
    let level = fs::read_to_string(project.join("tests/fixtures/stride.level.json")).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    let inputs: Vec<u8> = serde_json::from_slice(
        &fs::read(project.join("tests/fixtures/stride.input.json")).unwrap(),
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
                "uninterrupted mismatch tick={tick} {:?}",
                a.first_difference(&b, &schema)
            );
        }
        if tick == 120 {
            fs::write(root.join("rust-uninterrupted-120.v10"), &actual).unwrap();
        }
        if tick < inputs.len() {
            session.advance(inputs[tick]).unwrap();
        }
    }
    assert_eq!(session.stats().completed_ticks, 800);
    assert_eq!(session.stats().tick, 419);
    assert_eq!(session.stats().restore_count, 0);
    assert!(session.stats().entity_steps > 0);
    assert!(session.stats().contacts > 0);
    assert!(session.stats().terrain_queries > 0);
    println!("STRIDE_UNINTERRUPTED_DONE snapshots=801 accepted_ticks={} saved_frame={} entity_steps={} contacts={} terrain_queries={}",session.stats().completed_ticks,session.stats().tick,session.stats().entity_steps,session.stats().contacts,session.stats().terrain_queries);
}
