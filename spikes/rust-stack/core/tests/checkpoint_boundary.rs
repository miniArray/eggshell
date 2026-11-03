//! Checkpoint semantic boundary refusals do not count as route coverage.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    Session,
};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "requires original checkpoint course artifacts on aka"]
fn invalid_checkpoint_memory_and_marker_restore_atomically() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let level = fs::read_to_string(std::env::var("CORE_FIXTURE_LEVEL").unwrap()).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let inputs: Vec<u8> =
        serde_json::from_slice(&fs::read(std::env::var("CORE_FIXTURE_INPUT").unwrap()).unwrap())
            .unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    for input in inputs {
        session.advance(input).unwrap();
        if session.presentation().player.life_phase == 6 {
            break;
        }
    }
    assert_eq!(session.presentation().player.life_phase, 6);
    let before = session.snapshot().unwrap();
    let wire = WireSnapshot::decode(&before, session.world().identity, &schema).unwrap();
    session.restore(&before).unwrap();
    let stats = session.stats().clone();
    let picture = session.presentation();
    let mut wrong_id = wire.clone();
    let coin = wire.entities.iter().find(|e| e.code == "o1").unwrap();
    let id = required(&coin.values, schema.entity_fields("o1"), "source_index").unwrap() + 1;
    let field = schema
        .level()
        .iter()
        .position(|f| f.0 == "checkpoint_id")
        .unwrap();
    wrong_id.level[field] = id;
    let mut bonus = wire.clone();
    let marker = bonus.entities.iter_mut().find(|e| e.code == "o6").unwrap();
    let field = schema
        .entity_fields("o6")
        .iter()
        .position(|f| f.0 == "health_bonus")
        .unwrap();
    marker.values[field] = 11;
    let mut awards = wire.clone();
    let field = schema
        .player()
        .iter()
        .position(|f| f.0 == "checkpoint_awards")
        .unwrap();
    awards.player[field] = 31;
    for malformed in [wrong_id, bonus, awards] {
        let bytes = malformed.encode(&schema).unwrap();
        assert!(session.restore(&bytes).is_err());
        assert_eq!(session.snapshot().unwrap(), before);
        assert_eq!(session.stats(), &stats);
        assert_eq!(session.presentation(), picture);
    }
    println!("CHECKPOINT_REFUSAL_DONE cases=3 normally_reached_checkpoint=true atomic_snapshot_stats_presentation=true");
}
