//! Whole-pack admission sweep (aka only, private corpus). For each level: load it strictly,
//! run 600 idle steps, save and restore. Writes one JSON line per level to PACK_SWEEP_OUT:
//! the result, or the first refusal reason. Not a parity claim; it measures coverage.
use eggshell_spike_core::{Error, Session};
use std::{fs, io::Write, path::PathBuf};

#[test]
#[ignore = "requires the private 858-level corpus on aka"]
fn pack_sweep_admission_and_idle() {
    let home = PathBuf::from(std::env::var("HOME").unwrap());
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let collision = fs::read_to_string(project.join("src/level/collision_table.json")).unwrap();
    let schema = fs::read_to_string(
        home.join("eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json"),
    )
    .unwrap();
    let dir = home.join(".local/share/eggshell-run/corpus/levels");
    let out = std::env::var("PACK_SWEEP_OUT").expect("PACK_SWEEP_OUT");
    let mut out = fs::File::create(out).unwrap();
    let mut names: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "json"))
        .collect();
    names.sort();
    let (mut ok, mut refused, mut failed) = (0, 0, 0);
    for path in names {
        let id = path.file_stem().unwrap().to_string_lossy().to_string();
        let level = fs::read_to_string(&path).unwrap();
        let result = std::panic::catch_unwind(|| -> Result<(), String> {
            let mut session = Session::load(&level, &collision, &schema).map_err(|e| match e {
                Error::Unsupported { requirements } => format!("UNSUPPORTED {requirements:?}"),
                other => format!("ERROR {other:?}"),
            })?;
            for tick in 0..600 {
                session
                    .advance(0)
                    .map_err(|e| format!("STEP {tick} {e:?}"))?;
            }
            let saved = session.snapshot().map_err(|e| format!("SNAPSHOT {e:?}"))?;
            session.restore(&saved).map_err(|e| format!("RESTORE {e:?}"))?;
            Ok(())
        });
        let (status, reason) = match result {
            Ok(Ok(())) => {
                ok += 1;
                ("ok", String::new())
            }
            Ok(Err(reason)) if reason.starts_with("UNSUPPORTED") => {
                refused += 1;
                ("refused", reason)
            }
            Ok(Err(reason)) => {
                failed += 1;
                ("failed", reason)
            }
            Err(_) => {
                failed += 1;
                ("panic", String::new())
            }
        };
        let reason: String = reason.chars().take(400).collect();
        writeln!(
            out,
            "{}",
            serde_json::json!({"id": id, "status": status, "reason": reason})
        )
        .unwrap();
    }
    println!("PACK_SWEEP_DONE ok={ok} refused={refused} failed={failed}");
}
