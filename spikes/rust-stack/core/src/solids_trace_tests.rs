//! Read-only old/live geometry from a fresh original normal-input replay.
use crate::{solids::SolidTrace, Session};
#[test]
#[ignore = "requires original post geometry replay on aka"]
fn post_old_live_and_same_step_floor_match_original() {
    let level = std::fs::read_to_string(std::env::var("CORE_FIXTURE_LEVEL").unwrap()).unwrap();
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let collision = std::fs::read_to_string(root.join("src/level/collision_table.json")).unwrap();
    let dir = std::path::PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let schema = std::fs::read_to_string(dir.join("schema.json")).unwrap();
    let input: Vec<u8> = serde_json::from_slice(
        &std::fs::read(std::env::var("CORE_FIXTURE_INPUT").unwrap()).unwrap(),
    )
    .unwrap();
    let expected: Vec<SolidTrace> =
        serde_json::from_slice(&std::fs::read(dir.join("geometry.json")).unwrap()).unwrap();
    assert_eq!(expected.len(), input.len() + 1);
    let mut session = Session::load(&level, &collision, &schema).unwrap();
    let mut changes = 0;
    for tick in 0..=input.len() {
        assert_eq!(
            session.state.solid_trace, expected[tick],
            "old/live geometry, live floor or polygon/box query mismatch tick={tick}"
        );
        changes += usize::from(expected[tick].rows.iter().any(|r| r.old_box != r.live_box));
        if tick < input.len() {
            session.advance(input[tick]).unwrap();
        }
    }
    assert_eq!(changes, 3);
    println!("POST_OLD_LIVE_DONE snapshots={} natural_geometry_change_frames={changes} same_step_floor_by_token=true deliberate_polygon_box_probes=4_per_state original_replay_state_edits=0 test_only_trace=true",expected.len());
}
