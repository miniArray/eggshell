//! Boundary failures from a normal first impact, not injected gameplay coverage.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    Session,
};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "requires normal post-pound artifacts on aka"]
fn post_and_pound_boundaries_refuse_atomically() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let dir = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let level = fs::read_to_string(std::env::var("CORE_FIXTURE_LEVEL").unwrap()).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(dir.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let inputs: Vec<u8> =
        serde_json::from_slice(&fs::read(std::env::var("CORE_FIXTURE_INPUT").unwrap()).unwrap())
            .unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    for input in inputs.into_iter().take(121) {
        session.advance(input).unwrap();
    }
    assert_eq!(session.presentation().player.action, 3);
    let before = session.snapshot().unwrap();
    let wire = WireSnapshot::decode(&before, session.world().identity, &schema).unwrap();
    let post = wire.entities.iter().position(|e| e.id == "post96").unwrap();
    assert_eq!(
        required(
            &wire.entities[post].values,
            schema.entity_fields("o23"),
            "height"
        )
        .unwrap(),
        64 * 3600
    );
    assert_eq!(
        required(&wire.player, schema.player(), "move_impact").unwrap(),
        1
    );
    session.restore(&before).unwrap();
    let stats = session.stats().clone();
    let picture = session.presentation();
    for (field, value, is_player) in [
        ("height", -1, false),
        ("colour", 17, false),
        ("spiked", 2, false),
        ("move_look", 1, true),
        ("move_impact", -1, true),
        ("move_impact_x", i64::MAX, true),
    ] {
        let mut bad = wire.clone();
        let fields = if is_player {
            schema.player()
        } else {
            schema.entity_fields("o23")
        };
        let index = fields.iter().position(|f| f.0 == field).unwrap();
        if is_player {
            bad.player[index] = value;
        } else {
            bad.entities[post].values[index] = value;
        }
        assert!(
            session.restore(&bad.encode(&schema).unwrap()).is_err(),
            "field={field}"
        );
        assert_eq!(session.snapshot().unwrap(), before);
        assert_eq!(session.stats(), &stats);
        assert_eq!(session.presentation(), picture);
    }
    for input in [16, 64, 128, 48] {
        assert!(session.advance(input).is_err());
        assert_eq!(session.snapshot().unwrap(), before);
        assert_eq!(session.stats(), &stats);
        assert_eq!(session.presentation(), picture);
    }
    println!("POST_POUND_REFUSAL_DONE malformed_restore=6 unsupported_input=4 normally_reached_impact=1 atomic_snapshot_stats_presentation=true");
}

#[test]
#[ignore = "requires original quick-restart boundary artifacts on aka"]
fn pound_post_mutation_survives_dead_body_early_return() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let dir = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let level = fs::read_to_string(std::env::var("CORE_FIXTURE_LEVEL").unwrap()).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(dir.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    session
        .restore(&fs::read(dir.join("dead-before.v10")).unwrap())
        .unwrap();
    assert_eq!(session.presentation().player.life_phase, 3);
    session.advance(0).unwrap();
    let actual = session.snapshot().unwrap();
    let expected = fs::read(dir.join("dead-after.v10")).unwrap();
    if actual != expected {
        let a = WireSnapshot::decode(&expected, session.world().identity, &schema).unwrap();
        let b = WireSnapshot::decode(&actual, session.world().identity, &schema).unwrap();
        panic!(
            "dead-body callback mismatch: {:?}",
            a.first_difference(&b, &schema)
        );
    }
    println!("POST_DEAD_BODY_BOUNDARY_DONE original_quick_restart=true prefix_inputs=120 literal_after_early_return=true target_activity_claim=false");
}
