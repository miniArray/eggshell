//! Public invented course; the v10 fixture was written by unchanged main 0ccdc3f.
use eggshell_spike_core::{schema::Schema, wire::WireSnapshot, Session};

const LEVEL: &str = include_str!("fixtures/actors_target.level.json");
const COLLISION: &str = include_str!("../../../../data/collision_table.json");
const METADATA: &str = include_str!("../../../../data/snapshot-schema-v11.json");
const LEGACY_SAVE: &[u8] = include_bytes!("fixtures/v10-0ccdc3f-actors-t160.state");

#[test]
fn current_main_v10_save_migrates_and_continues_for_600_steps() {
    assert_eq!(WireSnapshot::format_version(LEGACY_SAVE).unwrap(), 10);
    let mut session = Session::load(LEVEL, COLLISION, METADATA).unwrap();
    let old = WireSnapshot::decode(
        LEGACY_SAVE,
        session.world().identity,
        &Schema::legacy().unwrap(),
    )
    .unwrap();
    session.restore(LEGACY_SAVE).unwrap();
    let current = Schema::current().unwrap();
    let migrated = session.snapshot().unwrap();
    assert_eq!(WireSnapshot::format_version(&migrated).unwrap(), 11);
    let wire = WireSnapshot::decode(&migrated, session.world().identity, &current).unwrap();
    for name in [
        "x",
        "y",
        "vx",
        "vy",
        "health",
        "life_phase",
        "previous_input",
        "move_emit_serial",
    ] {
        let before = Schema::legacy()
            .unwrap()
            .player()
            .iter()
            .position(|f| f.0 == name)
            .unwrap();
        let after = current.player().iter().position(|f| f.0 == name).unwrap();
        assert_eq!(old.player[before], wire.player[after], "{name}");
    }
    for tick in 0..600 {
        let input = match tick % 125 {
            0..=39 | 54..=73 | 87..=116 => 2,
            40..=53 => 6,
            74 => 8,
            _ => 0,
        };
        session
            .advance(input)
            .unwrap_or_else(|error| panic!("continuation tick={tick}: {error}"));
        if tick % 60 == 0 {
            let saved = session.snapshot().unwrap();
            session.restore(&saved).unwrap();
            assert_eq!(session.snapshot().unwrap(), saved);
        }
    }
}

#[test]
fn legacy_metadata_is_still_accepted_but_new_saves_are_v11() {
    let legacy = include_str!("../../../../data/snapshot-schema-v10.json");
    let mut session = Session::load(LEVEL, COLLISION, legacy).unwrap();
    let saved = session.snapshot().unwrap();
    assert_eq!(WireSnapshot::format_version(&saved).unwrap(), 11);
    session.restore(&saved).unwrap();
    assert_eq!(session.snapshot().unwrap(), saved);
}

#[test]
fn rejected_legacy_restore_does_not_change_session() {
    let mut session = Session::load(LEVEL, COLLISION, METADATA).unwrap();
    let before = session.snapshot().unwrap();
    let mut corrupt = LEGACY_SAVE.to_vec();
    corrupt[76] ^= 1;
    assert!(session.restore(&corrupt).is_err());
    assert_eq!(session.snapshot().unwrap(), before);
}
