//! Normal fixture controls. Oracle bytes compare, but never supply uninterrupted stepping state.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    Session,
};
use std::{fs, path::PathBuf};
fn run(restores: bool) {
    let name = std::env::var("CORE_FIXTURE").unwrap();
    assert!(["bounce", "bounce.pad", "lagoon"].contains(&name.as_str()));
    let base = name.split('.').next().unwrap();
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let level =
        fs::read_to_string(project.join(format!("tests/fixtures/{base}.level.json"))).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let schema = Schema::parse(&metadata).unwrap();
    let inputs: Vec<u8> =
        serde_json::from_slice(&fs::read(std::env::var("CORE_FIXTURE_INPUT").unwrap()).unwrap())
            .unwrap();
    let stream = fs::read(root.join("snapshots.v10.stream")).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap_or_else(|error| {
        panic!("{name} next support/action gate at initialization: {error}")
    });
    let mut cursor = 0;
    let mut bridge_ticks = 0;
    let mut squash_ticks = 0;
    let mut tongue_ticks = 0;
    let mut swimming_ticks = 0;
    for tick in 0..=inputs.len() {
        let size = u32::from_le_bytes(stream[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4;
        let expected = &stream[cursor..cursor + size];
        cursor += size;
        let actual = session.snapshot().unwrap();
        let wire = WireSnapshot::decode(&actual, session.world().identity, &schema).unwrap();
        if actual != expected {
            let a = WireSnapshot::decode(expected, session.world().identity, &schema).unwrap();
            panic!(
                "{name} mismatch tick={tick}: {:?}",
                a.first_difference(&wire, &schema)
            );
        }
        let packet = session.presentation();
        bridge_ticks +=
            usize::from(required(&wire.player, schema.player(), "support_bridge").unwrap() != 0);
        tongue_ticks += usize::from(packet.player.action == 4);
        swimming_ticks += usize::from(packet.player.swimming);
        for (entity, picture) in wire.entities.iter().zip(&packet.entities) {
            if entity.code == "o11" {
                let fields = schema.entity_fields("o11");
                let remaining = required(&entity.values, fields, "squash").unwrap();
                let size = if required(&entity.values, fields, "large").unwrap() != 0 {
                    48.0
                } else {
                    32.0
                };
                let squash = remaining.min(12 - remaining) as f64;
                assert_eq!(
                    picture.visual.scale,
                    Some([
                        (size + 16.0 * squash / 6.0) / size,
                        (size - 16.0 * squash / 6.0) / size
                    ])
                );
                squash_ticks += usize::from(remaining != 0);
            }
        }
        assert_eq!(
            session.snapshot().unwrap(),
            actual,
            "presentation mutates saved state"
        );
        if restores && [0, 1, 6, 11, 66, 70, 75, 90, 160, 220, 350, 500].contains(&tick) {
            session.restore(expected).unwrap();
            assert_eq!(session.snapshot().unwrap(), expected);
        }
        if !restores && [1, 6, 11, 70, 75, 90, 160, 220, 350].contains(&tick) {
            fs::write(root.join(format!("rust-uninterrupted-{tick}.v10")), &actual).unwrap();
        }
        if tick < inputs.len() {
            session
                .advance(inputs[tick])
                .unwrap_or_else(|error| panic!("{name} next gate at tick={}: {error}", tick + 1));
        }
    }
    assert_eq!(cursor, stream.len());
    assert_eq!(session.stats().completed_ticks, inputs.len() as u64);
    assert_eq!(session.stats().restore_count, if restores { 12 } else { 0 });
    if name == "bounce.pad" {
        assert!(
            squash_ticks > 0,
            "named normal route must actually activate the pad"
        );
    } else {
        assert!(tongue_ticks > 0);
    }
    println!("FIXTURE_VERTICAL_DONE fixture={name} snapshots={} accepted_ticks={} saved_frame={} uninterrupted={} A_to_B_restores={} bridge_support_ticks={bridge_ticks} pad_squash_ticks={squash_ticks} tongue_ticks={tongue_ticks} swimming_ticks={swimming_ticks} target_admission=refused",inputs.len()+1,session.stats().completed_ticks,session.stats().tick,!restores,session.stats().restore_count);
}
#[test]
#[ignore = "requires original Godot fixture stream"]
fn admitted_fixture_has_uninterrupted_every_tick_parity() {
    run(false);
}
#[test]
#[ignore = "requires original Godot fixture stream"]
fn admitted_fixture_has_original_restore_continuation() {
    run(true);
}
#[test]
#[ignore = "requires original Godot schema"]
fn unsupported_tongue_food_contact_refuses_atomically() {
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let root = PathBuf::from(std::env::var("CORE_FIXTURE_DIR").unwrap());
    let level = fs::read_to_string(project.join("tests/fixtures/stride.level.json")).unwrap();
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let metadata = fs::read_to_string(root.join("schema.json")).unwrap();
    let inputs: Vec<u8> = serde_json::from_slice(
        &fs::read(project.join("tests/fixtures/stride.damage.input.json")).unwrap(),
    )
    .unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    for input in &inputs[..152] {
        session.advance(*input).unwrap();
    }
    let before = session.snapshot().unwrap();
    let picture = session.presentation();
    let stats = session.stats().clone();
    let error = session.advance(10).unwrap_err();
    assert!(
        matches!(error,eggshell_spike_core::Error::Unsupported{requirements} if requirements==["tongue food capture/request consumer is not implemented"])
    );
    assert_eq!(session.snapshot().unwrap(), before);
    assert_eq!(session.presentation(), picture);
    assert_eq!(session.stats().completed_ticks, stats.completed_ticks);
    assert_eq!(session.stats().terrain_queries, stats.terrain_queries);
    assert_eq!(session.stats().contacts, stats.contacts);
    println!("FOOD_REFUSAL_DONE normally_reached=true atomic=true");
}
