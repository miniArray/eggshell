//! Malformed suffix payloads are boundary tests, not legal-route coverage.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    Session,
};
use sha2::{Digest, Sha256};
use std::{fs, path::PathBuf};
// Deliberately preserve the checksum while corrupting payload contracts. The normal
// encoder correctly refuses these malformed states before producing bytes.
fn checksum(mut bytes: Vec<u8>) -> Vec<u8> {
    bytes.truncate(bytes.len() - 32);
    let digest = Sha256::digest(&bytes);
    bytes.extend_from_slice(&digest);
    bytes
}
#[test]
#[ignore = "requires original normal stilt stream on aka"]
fn malformed_runtime_suffix_restore_is_atomic() {
    if std::env::var("CORE_FIXTURE").as_deref() != Ok("stilts_target") {
        return;
    }
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
    for input in &inputs[..107] {
        session.advance(*input).unwrap();
    }
    let before = session.snapshot().unwrap();
    let wire = WireSnapshot::decode(&before, session.world().identity, &schema).unwrap();
    session
        .restore(&before)
        .expect("normally reached runtime payload must restore");
    assert_eq!(session.snapshot().unwrap(), before);
    let stats = session.stats().clone();
    let picture = session.presentation();
    let row = wire.entities.last().unwrap();
    assert_eq!(row.code, "e1");
    assert_eq!(
        required(&row.values, schema.entity_fields("e1"), "source_index").unwrap(),
        -1
    );
    let serial_index = schema
        .level()
        .iter()
        .position(|f| f.0 == "dynamic_serial")
        .unwrap();
    let token_index = schema
        .entity_fields("e1")
        .iter()
        .position(|f| f.0 == "token")
        .unwrap();
    let request_index = schema
        .entity_fields("e1")
        .iter()
        .position(|f| f.0 == "request_cursor")
        .unwrap();
    let mut stale = before.clone();
    let at = 76 + serial_index * 8;
    stale[at..at + 8].copy_from_slice(&1i64.to_le_bytes());
    let values_at = before.len() - 32 - row.values.len() * 8;
    let mut token = before.clone();
    let at = values_at + token_index * 8;
    token[at..at + 8].copy_from_slice(&(row.values[token_index] + 1).to_le_bytes());
    let mut request = before.clone();
    let at = values_at + request_index * 8;
    request[at..at + 8].copy_from_slice(&1i64.to_le_bytes());
    let row_start = values_at - 12 - row.code.len() - row.id.len();
    let mut duplicate = before[..before.len() - 32].to_vec();
    duplicate.extend_from_slice(&before[row_start..before.len() - 32]);
    duplicate.extend_from_slice(&[0; 32]);
    let at = 76 + 8 * (schema.level().len() + schema.player().len());
    duplicate[at..at + 4].copy_from_slice(&((wire.entities.len() + 1) as u32).to_le_bytes());
    for malformed in [stale, duplicate, token, request] {
        let bytes = checksum(malformed);
        assert!(session.restore(&bytes).is_err());
        assert_eq!(session.snapshot().unwrap(), before);
        assert_eq!(session.stats(), &stats);
        assert_eq!(session.presentation(), picture);
    }
    println!("RUNTIME_SUFFIX_REFUSAL_DONE cases=4 normally_reached_live_runtime=true atomic=true typed_request_refusal=true");
}
