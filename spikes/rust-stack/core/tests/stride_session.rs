use eggshell_spike_core::{schema::Schema, wire::WireSnapshot, Error, Session};
use std::{fs, path::PathBuf};
fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../tests/fixtures")
        .join(name)
}
fn data() -> (String, String, String, PathBuf) {
    let root = PathBuf::from(std::env::var("CORE_ORACLE_DIR").unwrap());
    (
        fs::read_to_string(fixture("stride.level.json")).unwrap(),
        fs::read_to_string(fixture("../../data/collision_table.json")).unwrap(),
        fs::read_to_string(root.join("schema.json")).unwrap(),
        root,
    )
}
#[test]
#[ignore = "requires fresh original Godot Stride trace"]
fn stride_session_produces_original_every_tick_state_and_restores() {
    let (level, collision, metadata, root) = data();
    let schema = Schema::parse(&metadata).unwrap();
    let mut session = Session::load(&level, &collision, &metadata).unwrap();
    let stream = fs::read(root.join("snapshots.v10.stream")).unwrap();
    let inputs: Vec<u8> =
        serde_json::from_slice(&fs::read(fixture("stride.input.json")).unwrap()).unwrap();
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
                "first mismatch tick={tick} {:?}",
                a.first_difference(&b, &schema)
            );
        }
        if tick % 60 == 0 {
            session.restore(expected).unwrap();
            assert_eq!(session.snapshot().unwrap(), expected);
        }
        if tick == 120 {
            fs::write(root.join("rust-at-120.v10"), &actual).unwrap();
        }
        if tick < inputs.len() {
            session.advance(inputs[tick]).unwrap();
        }
    }
    assert_eq!(session.presentation().tick, 419);
    println!(
        "STRIDE_SESSION_DONE input_ticks={} saved_frame={} snapshots={} A_to_B_restores=14",
        inputs.len(),
        session.presentation().tick,
        inputs.len() + 1
    );
}
#[test]
#[ignore = "requires fresh original Godot Stride schema"]
fn target_loads_and_idles_without_refusal() {
    let (_, collision, metadata, _) = data();
    // P1 admits the 204-object target: every code it places is implemented.
    let target = fs::read_to_string(
        PathBuf::from(std::env::var("HOME").unwrap())
            .join(".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"),
    )
    .unwrap();
    let mut session = match Session::load(&target, &collision, &metadata) {
        Ok(session) => session,
        Err(Error::Unsupported { requirements }) => panic!("target refused: {requirements:?}"),
        Err(error) => panic!("target load error: {error:?}"),
    };
    for tick in 0..2400 {
        if let Err(error) = session.advance(0) {
            panic!("idle tick {tick} refused: {error:?}");
        }
    }
    let snapshot = session.snapshot().unwrap();
    session.restore(&snapshot).unwrap();
    assert_eq!(session.snapshot().unwrap(), snapshot);
    println!("TARGET_IDLE_DONE ticks=2400 round_trip=true");
}
