//! Host only (aka): the level list index for the device bundle. Lists a level folder in
//! level_list.gd order and, for each readable level, records whether this build can play
//! it: core admission, scene preparation, and a short idle run with a picture per step.
//! A level that fails any of these is listed as unavailable with the reason.
use crate::{
    level_list::{Entry, entry, natural_cmp, refusal_reason},
    pack::Pack,
    scene::Scene,
};
use eggshell_spike_core::Session;
use std::path::{Path, PathBuf};

/// level_list.gd EXTENSIONS, MAX_FILES; level_code.gd MAX_CODE_BYTES.
const EXTENSIONS: [&str; 2] = ["json", "txt"];
const MAX_FILES: usize = 4096;
const MAX_CODE_BYTES: u64 = 16 * 1024 * 1024;
/// Idle steps drawn at the start of each level (one picture per step, zoom 0).
pub const CHECK_STEPS: u64 = 60;
const CONTAINER: [f64; 2] = [640.0, 480.0];

fn read(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))
}

/// The core's refusal text for a placement form it does not spawn (state.rs spawn_rows).
const GENERIC_PLACEMENT_REFUSAL: &str = "Not supported yet: fixture entity form";

/// Placed object codes of every map, in first-seen order without repeats.
fn placed_codes(level: &str, collision: &str) -> Vec<String> {
    let mut codes = Vec::new();
    if let Ok(world) = eggshell_spike_core::World::compile(level, collision) {
        for p in world.maps.iter().flat_map(|m| &m.placements) {
            if !codes.contains(&p.code) {
                codes.push(p.code.clone());
            }
        }
    }
    codes
}

/// Why this build cannot play the level, or None when it can.
fn playable(
    level: &str,
    collision: &str,
    schema: &str,
    pack: &Pack,
    metrics: &Path,
) -> Option<String> {
    let mut session = match Session::load(level, collision, schema) {
        Ok(s) => s,
        Err(e) => return Some(refusal_reason(&e)),
    };
    let codes = session.admission_report().admitted_codes.clone();
    let mut scene = match Scene::prepare(session.world(), &codes, pack, metrics) {
        Ok(s) => s,
        Err(e) => return Some(format!("Cannot draw: {e}")),
    };
    if let Err(e) = scene.prepare_headless_assets(pack) {
        return Some(format!("Cannot draw: {e}"));
    }
    session.configure_presentation_index(scene.absolute_origin_guard());
    for step in 0..=CHECK_STEPS {
        if step > 0
            && let Err(e) = session.advance(0)
        {
            return Some(format!("Stops after {step} steps: {}", refusal_reason(&e)));
        }
        let (map_index, focus) = session.presentation_view();
        let picture = scene
            .presentation_region(map_index, focus, CONTAINER, 0)
            .and_then(|region| {
                let p = session.presentation_region(region);
                scene.picture(&p, CONTAINER, 0)
            });
        if let Err(e) = picture {
            return Some(format!("Cannot draw: {e}"));
        }
    }
    None
}

/// `--level-index FOLDER COLLISION SCHEMA PACK INVENTORY VIEW_METRICS OUT`
pub fn run(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let args: Vec<String> = arguments.collect();
    if args.len() != 7 {
        return Err("--level-index FOLDER COLLISION SCHEMA PACK INVENTORY VIEW_METRICS OUT".into());
    }
    let folder = PathBuf::from(&args[0]);
    let collision = read(Path::new(&args[1]))?;
    let schema = read(Path::new(&args[2]))?;
    let pack = Pack::open(Path::new(&args[3]), Path::new(&args[4]))?;
    let metrics = PathBuf::from(&args[5]);
    let mut names: Vec<String> = std::fs::read_dir(&folder)
        .map_err(|e| format!("Level folder not found: {}: {e}", folder.display()))?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|n| {
            !n.starts_with('.')
                && Path::new(n)
                    .extension()
                    .and_then(|x| x.to_str())
                    .is_some_and(|x| EXTENSIONS.contains(&x.to_lowercase().as_str()))
        })
        .collect();
    names.sort_by(|a, b| natural_cmp(a, b));
    let truncated = names.len() > MAX_FILES;
    names.truncate(MAX_FILES);
    let mut levels: Vec<Entry> = Vec::with_capacity(names.len());
    let mut supported = std::collections::BTreeSet::new();
    let mut generic = Vec::new();
    let started = std::time::Instant::now();
    for name in names {
        let path = folder.join(&name);
        let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
        let mut e = if size > MAX_CODE_BYTES {
            let mut e = entry(&name, "");
            e.error = "Larger than 16 MiB".into();
            e
        } else {
            entry(&name, &std::fs::read_to_string(&path).unwrap_or_default())
        };
        if e.ok {
            let code = read(&path)?;
            let codes = placed_codes(&code, &collision);
            let reason = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                playable(&code, &collision, &schema, &pack, &metrics)
            }))
            .unwrap_or_else(|_| Some("Internal error while checking".into()));
            match reason {
                Some(reason) => {
                    e.ok = false;
                    e.error = reason;
                    generic.push((levels.len(), codes));
                }
                None => supported.extend(codes),
            }
        }
        levels.push(e);
    }
    // The core names only its generic placement refusal; name the placed objects that no
    // playable level uses (an approximation: a code can be supported in other forms).
    for (index, codes) in generic {
        let e = &mut levels[index];
        if e.error == GENERIC_PLACEMENT_REFUSAL {
            let missing: Vec<&str> = codes
                .iter()
                .filter(|c| !supported.contains(*c))
                .map(String::as_str)
                .collect();
            if !missing.is_empty() {
                e.error = format!("Not supported yet: objects {}", missing.join(", "));
            }
        }
    }
    for e in &levels {
        println!(
            "LEVEL_INDEX_ENTRY file={} ok={} reason={:?}",
            e.file, e.ok, e.error
        );
    }
    let playable_count = levels.iter().filter(|e| e.ok).count();
    let index = serde_json::json!({
        "levels": levels,
        "truncated": truncated,
        "check": format!("core load, scene preparation, {CHECK_STEPS} idle steps drawn at zoom 0"),
    });
    std::fs::write(
        &args[6],
        serde_json::to_vec_pretty(&index).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    println!(
        "LEVEL_INDEX_DONE levels={} playable={playable_count} seconds={:.1} out={}",
        levels.len(),
        started.elapsed().as_secs_f64(),
        args[6]
    );
    Ok(())
}
