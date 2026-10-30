//! Private oracle data is supplied at runtime, never embedded in source or binaries.
use eggshell_spike_core::{schema::Schema, wire::WireSnapshot};
use std::{fs, path::PathBuf};

fn artifacts() -> PathBuf {
    assert_eq!(
        std::env::var("HOSTNAME").unwrap_or_default(),
        "aka",
        "oracle tests must run on aka"
    );
    PathBuf::from(std::env::var("CORE_ORACLE_DIR").expect("CORE_ORACLE_DIR"))
}

#[test]
#[ignore = "requires freshly exported private Godot oracle"]
fn original_v10_every_tick_round_trips_without_omitting_unused_schemas() {
    let path = artifacts();
    let schema_json = fs::read_to_string(path.join("schema.json")).unwrap();
    let schema = Schema::parse(&schema_json).unwrap();
    assert!(schema.entities().len() > 100);
    assert!(schema.entity("e35").is_some());
    assert!(schema.entity("fire_shot").is_some());
    let initial = fs::read(path.join("initial.v10")).unwrap();
    let identity: [u8; 32] = initial[12..44].try_into().unwrap();
    let stream = fs::read(path.join("snapshots.v10.stream")).unwrap();
    let mut cursor = 0;
    let mut count = 0;
    while cursor < stream.len() {
        let size = u32::from_le_bytes(stream[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4;
        let bytes = &stream[cursor..cursor + size];
        let decoded = WireSnapshot::decode(bytes, identity, &schema).unwrap();
        assert_eq!(decoded.encode(&schema).unwrap(), bytes, "snapshot {count}");
        assert!(decoded.first_difference(&decoded, &schema).is_none());
        cursor += size;
        count += 1;
    }
    assert!(count > 1);
    println!(
        "WIRE_ORACLE_DONE snapshots={count} codes={}",
        schema.entities().len()
    );
}

#[test]
#[ignore = "requires freshly exported private Godot oracle"]
fn corrupt_snapshot_and_schema_are_rejected() {
    let path = artifacts();
    let schema_json = fs::read_to_string(path.join("schema.json")).unwrap();
    let schema = Schema::parse(&schema_json).unwrap();
    let bytes = fs::read(path.join("initial.v10")).unwrap();
    let identity = bytes[12..44].try_into().unwrap();
    for length in [0, 1, 11, 75, bytes.len() - 1] {
        assert!(WireSnapshot::decode(&bytes[..length], identity, &schema).is_err());
    }
    for offset in [0, 8, 12, 44, 76, bytes.len() - 1] {
        let mut broken = bytes.clone();
        broken[offset] ^= 1;
        assert!(WireSnapshot::decode(&broken, identity, &schema).is_err());
    }
    assert!(WireSnapshot::decode(&bytes, [0; 32], &schema).is_err());
    let subset = schema_json.replace(
        "12034df2601b61728f41efa24c05b3679830af0ba217a41e5c1446441b6052ee",
        &"0".repeat(64),
    );
    assert!(Schema::parse(&subset).is_err());
    println!("WIRE_REJECTION_DONE");
}
