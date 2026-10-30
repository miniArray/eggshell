//! Inspect parent-owned legal route evidence; never a substitute candidate advance.
use eggshell_spike_core::{
    schema::Schema,
    wire::{required, WireSnapshot},
    World,
};
use std::{fs, path::PathBuf};
#[test]
#[ignore = "requires private parent target-search-v2 endpoint on aka"]
fn parent_legal_route_runtime_suffix() {
    let home = PathBuf::from(std::env::var("HOME").unwrap());
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let core = home.join("eggshell-remote/artifacts/full-rust-ab/core");
    let schema =
        Schema::parse(&fs::read_to_string(core.join("target-4.7.2/schema.json")).unwrap()).unwrap();
    let world = World::compile(
        &fs::read_to_string(
            home.join(".local/share/eggshell-run/corpus/levels/6600ab52a3bb0805d316b9f1.json"),
        )
        .unwrap(),
        &fs::read_to_string(project.join("src/level/collision_table.json")).unwrap(),
    )
    .unwrap();
    let bytes = fs::read(
        home.join("eggshell-remote/artifacts/full-rust-ab/routes/target-search-v2/finish.v10"),
    )
    .unwrap();
    let snapshot = WireSnapshot::decode(&bytes, world.identity, &schema).unwrap();
    let mut rows = 0;
    for row in &snapshot.entities {
        let fields = schema.entity_fields(&row.code);
        if required(&row.values, fields, "source_index").unwrap() == -1 {
            rows += 1;
            let variant = fields
                .iter()
                .position(|f| f.0 == "variant")
                .map(|index| row.values[index]);
            println!(
                "PARENT_V2_RUNTIME_ROW id={} code={} token={} variant={variant:?} status={}",
                row.id,
                row.code,
                required(&row.values, fields, "token").unwrap(),
                required(&row.values, fields, "status").unwrap()
            );
        }
    }
    println!("PARENT_V2_ENDPOINT_INSPECTED rows={} retained_runtime_rows={rows} dynamic_serial={} candidate_admission=not_claimed",snapshot.entities.len(),required(&snapshot.level,schema.level(),"dynamic_serial").unwrap());
}
