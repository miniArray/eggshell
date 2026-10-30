use eggshell_spike_core::{schema::Schema, wire::WireSnapshot, Session};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "requires original Godot Stride schema"]
fn overflowing_saved_frame_refuses_atomically_instead_of_panicking() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_ORACLE_DIR").unwrap());
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(
        &fs::read_to_string(project.join("tests/fixtures/stride.level.json")).unwrap(),
        &fs::read_to_string(project.join("src/level/collision_table.json")).unwrap(),
        &metadata,
    )
    .unwrap();
    let initial = session.snapshot().unwrap();
    let mut state = WireSnapshot::decode(&initial, session.world().identity, &schema).unwrap();
    let frame = schema.level().iter().position(|f| f.0 == "frame").unwrap();
    state.level[frame] = i64::MAX;
    let bytes = state.encode(&schema).unwrap();
    session.restore(&bytes).unwrap();
    let accepted = session.stats().completed_ticks;
    assert!(session.advance(2).is_err());
    assert_eq!(session.snapshot().unwrap(), bytes);
    assert_eq!(session.stats().completed_ticks, accepted);
}
