//! Real Stride damage trace. The oracle is a comparator, not candidate stepping state.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    Session,
};
use std::{collections::BTreeSet, fs, path::PathBuf};
fn run(restores: bool) {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_DAMAGE_DIR").unwrap());
    let level = fs::read_to_string(project.join("tests/fixtures/stride.level.json")).unwrap();
    let collision = fs::read_to_string(project.join("data/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    let inputs: Vec<u8> = serde_json::from_slice(
        &fs::read(project.join("tests/fixtures/stride.damage.input.json")).unwrap(),
    )
    .unwrap();
    let stream = fs::read(root.join("snapshots.v10.stream")).unwrap();
    let mut cursor = 0;
    let mut phases = BTreeSet::new();
    let mut modes = BTreeSet::new();
    let mut min_health = 30;
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
        let p = session.presentation();
        phases.insert(p.player.life_phase);
        modes.insert(p.companions.mode);
        min_health = min_health.min(p.hud.health);
        let decoded = WireSnapshot::decode(&actual, session.world().identity, &schema).unwrap();
        assert_eq!(
            p.hud.health,
            required(&decoded.player, schema.player(), "health").unwrap()
        );
        assert_eq!(
            p.companions.mode,
            required(&decoded.player, schema.player(), "companion_mode").unwrap()
        );
        assert_eq!(
            session.snapshot().unwrap(),
            actual,
            "presentation must be read-only"
        );
        if restores && [0, 153, 154, 170, 190, 220, 280, 350, 500].contains(&tick) {
            session.restore(expected).unwrap();
            assert_eq!(session.snapshot().unwrap(), expected);
        }
        if !restores && [153, 190, 220, 350].contains(&tick) {
            fs::write(root.join(format!("rust-uninterrupted-{tick}.v10")), &actual).unwrap();
        }
        if tick < inputs.len() {
            session
                .advance(inputs[tick])
                .unwrap_or_else(|error| panic!("damage rejected tick={}: {error}", tick + 1));
        }
    }
    assert_eq!(session.stats().completed_ticks, 800);
    assert_eq!(session.stats().tick, 599);
    assert!(min_health < 10);
    assert_eq!(phases, BTreeSet::from([0, 1, 7, 8]));
    assert_eq!(modes, BTreeSet::from([0, 1, 2, 3]));
    assert!(session.stats().damage_events > 0);
    if restores {
        assert_eq!(session.stats().restore_count, 9);
    } else {
        assert_eq!(session.stats().restore_count, 0);
    }
    println!("STRIDE_DAMAGE_DONE uninterrupted={} snapshots=801 accepted_ticks=800 saved_frame=599 health_min={min_health} phases={phases:?} companion_modes={modes:?} A_to_B_restores={}",!restores,session.stats().restore_count);
}
#[test]
#[ignore = "requires original Godot Stride damage trace"]
fn stride_damage_original_every_tick_parity() {
    run(false);
}
#[test]
#[ignore = "requires original Godot Stride damage trace"]
fn stride_damage_original_restore_continuation() {
    run(true);
}
