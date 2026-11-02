//! Throwaway host diagnosis. No simulation or drawing optimizations.
use eggshell_spike_core::Session;
use std::time::Instant;

#[inline(never)]
pub fn profile_step(session: &mut Session, input: u8) -> Result<(), eggshell_spike_core::Error> {
    let result = session.advance(input);
    std::hint::black_box(session.stats().tick);
    result
}
fn load(args: &[String]) -> Result<Session, String> {
    let read = |i: usize| std::fs::read_to_string(&args[i]).map_err(|e| e.to_string());
    let method = if args[4] == "real-screen" {
        Session::load_benchmark_real_screen
    } else {
        Session::load_benchmark_unverified
    };
    method(&read(0)?, &read(1)?, &read(2)?).map_err(|e| e.to_string())
}
pub fn profile_host(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let args: Vec<_> = arguments.collect();
    if args.len() != 5 {
        return Err("profile-host LEVEL COLLISION SCHEMA TICKS real-screen|synthetic".into());
    }
    let mut session = load(&args)?;
    let ticks = args[3].parse::<usize>().map_err(|e| e.to_string())?;
    // HOST_SIM_INPUT: a JSON array of input masks (cycled); idle without it.
    let inputs: Vec<u8> = match std::env::var("HOST_SIM_INPUT") {
        Ok(path) => {
            serde_json::from_str(&std::fs::read_to_string(path).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?
        }
        Err(_) => vec![0],
    };
    let mut ms = Vec::with_capacity(ticks);
    let before = session.stats().entity_steps;
    for tick in 0..ticks {
        let now = Instant::now();
        profile_step(&mut session, inputs[tick % inputs.len().max(1)])
            .map_err(|e| e.to_string())?;
        ms.push(now.elapsed().as_secs_f64() * 1000.0);
    }
    ms.sort_by(f64::total_cmp);
    println!(
        "HOST_SIM_PROFILE {}",
        serde_json::json!({"level":args[0],"calls":ticks,"saved_tick":session.stats().tick,"entity_steps":session.stats().entity_steps-before,"step_ms_p50":ms[ticks/2],"step_ms_p95":ms[ticks*95/100],"step_ms_p99":ms[ticks*99/100],"step_ms_max":ms[ticks-1],"host_only":true,"audio":"disabled","saves":"disabled","profile_scope":"profile_step only; initialization outside marker"})
    );
    Ok(())
}

/// Old-vs-new equality trace. Per tick: the full presentation, the snapshot
/// bytes (or its error) and the scene quads at zooms 0..=2, chained by SHA-256.
#[cfg(feature = "benchmark-work-counters")]
pub fn trace_host(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    use crate::{pack::Pack, scene::Scene};
    use sha2::{Digest, Sha256};
    use std::path::Path;
    let args: Vec<_> = arguments.collect();
    if args.len() != 8 {
        return Err(
            "trace-host LEVEL COLLISION SCHEMA TICKS real-screen|synthetic PACK INVENTORY METRICS"
                .into(),
        );
    }
    let mut session = load(&args)?;
    let pack = Pack::open(Path::new(&args[5]), Path::new(&args[6]))?;
    let prepare = if args[4] == "real-screen" {
        Scene::prepare_benchmark_real_screen
    } else {
        Scene::prepare
    };
    let mut scene = prepare(
        session.world(),
        &session.admission_report().admitted_codes,
        &pack,
        Path::new(&args[7]),
    )?;
    scene.prepare_headless_assets(&pack)?;
    session.configure_presentation_index(scene.absolute_origin_guard());
    let ticks = args[3].parse::<usize>().map_err(|e| e.to_string())?;
    let mut chain = [0u8; 32];
    for tick in 1..=ticks {
        profile_step(&mut session, 0).map_err(|e| e.to_string())?;
        let mut h = Sha256::new();
        h.update(chain);
        h.update(format!("{:?}", session.presentation()));
        match session.snapshot() {
            Ok(bytes) => h.update(&bytes),
            Err(e) => h.update(format!("snapshot-error {e:?}")),
        }
        // TRACE_ZOOM_MIN=-1 also checks the 1x zoom-out (not part of the gate trace).
        let first_zoom: i32 = std::env::var("TRACE_ZOOM_MIN")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        for zoom in first_zoom..=2 {
            let (map, focus) = session.presentation_view();
            let region = scene.presentation_region(map, focus, [640.0, 480.0], zoom)?;
            let p = session.presentation_region(region);
            h.update(format!("{p:?}"));
            let picture = scene.picture(&p, [640.0, 480.0], zoom)?;
            if tick == 1 && zoom == 0 && std::env::var_os("TRACE_DUMP_QUADS").is_some() {
                for (n, q) in picture
                    .world
                    .iter()
                    .chain(&picture.hud)
                    .enumerate()
                    .step_by(7)
                    .take(40)
                {
                    println!(
                        "QUAD n={n} image={} corners={:?} uv={:?}",
                        q.image, q.corners, q.uv
                    );
                }
            }
            // Images by file name, so binding more art (new codes) keeps old traces.
            let files = scene.image_files();
            for quads in [&picture.world, &picture.hud, &picture.tint] {
                for q in quads.iter() {
                    h.update(format!(
                        "{}{:?}{:?}{:?}{:?}",
                        files.get(q.image).map_or("?", String::as_str),
                        q.corners,
                        q.uv,
                        q.color,
                        q.palette
                    ));
                }
                h.update(b"|");
            }
            h.update(format!("{}", picture.entity_bounds_in_view));
        }
        chain = h.finalize().into();
        if tick % 50 == 0 || tick == ticks {
            let hex: String = chain.iter().map(|b| format!("{b:02x}")).collect();
            println!("TRACE_HOST level={} tick={tick} chain={hex}", args[0]);
        }
    }
    Ok(())
}

#[cfg(feature = "benchmark-work-counters")]
#[derive(Default, serde::Serialize)]
pub struct EntityWork {
    pub visited: u64,
    pub selected: u64,
    pub art_built: u64,
    pub emitted: u64,
    pub quads_emitted: u64,
}
#[cfg(feature = "benchmark-work-counters")]
#[derive(Default, serde::Serialize)]
pub struct TileWork {
    pub source_layer: String,
    pub tilemap: String,
    pub z: i64,
    pub stored_cells: usize,
    pub visited: u64,
    pub emitted: u64,
}
#[cfg(feature = "benchmark-work-counters")]
#[derive(Default, serde::Serialize)]
pub struct SceneWork {
    pub art_cull_margin: f64,
    pub terrain_layers_total: usize,
    pub terrain_layers_selected: usize,
    pub presentation_entities: usize,
    pub tiles_visited: u64,
    pub tiles_emitted: u64,
    pub entity_row_visits: u64,
    pub entities_selected: u64,
    pub entities_art_built: u64,
    pub entities_emitted: u64,
    pub tile_layers: Vec<TileWork>,
    pub entity_layers: std::collections::BTreeMap<i64, EntityWork>,
}

#[cfg(feature = "benchmark-work-counters")]
pub fn work_host(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    use crate::{pack::Pack, scene::Scene};
    use std::path::Path;
    let args: Vec<_> = arguments.collect();
    if args.len() != 10 {
        return Err("work-host LEVEL COLLISION SCHEMA TICKS real-screen|synthetic ORIGINAL|- PACK INVENTORY METRICS REPORT".into());
    }
    let mut session = load(&args)?;
    let original: serde_json::Value = if args[5] == "-" {
        serde_json::Value::Null
    } else {
        serde_json::from_str(&std::fs::read_to_string(&args[5]).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?
    };
    let original = if let Some(s) = original.as_str() {
        serde_json::from_str(s).map_err(|e| e.to_string())?
    } else {
        original
    };
    let pack = Pack::open(Path::new(&args[6]), Path::new(&args[7]))?;
    let prepare = if args[4] == "real-screen" {
        Scene::prepare_benchmark_real_screen
    } else {
        Scene::prepare
    };
    let mut scene = prepare(
        session.world(),
        &session.admission_report().admitted_codes,
        &pack,
        Path::new(&args[8]),
    )?;
    scene.prepare_headless_assets(&pack)?;
    session.configure_presentation_index(scene.absolute_origin_guard());
    let ticks = args[3].parse::<usize>().map_err(|e| e.to_string())?;
    let mut records = Vec::new();
    let mut first_rows = serde_json::Value::Null;
    for tick in 1..=ticks {
        profile_step(&mut session, 0).map_err(|e| e.to_string())?;
        if tick == 1 {
            let mut original_codes = std::collections::BTreeMap::<String, u64>::new();
            let mut current_codes = std::collections::BTreeMap::<String, u64>::new();
            let mut runtime = 0;
            for row in &session.stats().benchmark_stepped_source_rows {
                if let Some(i) = row {
                    let p = &session.world().maps[0].placements[*i];
                    *current_codes.entry(p.code.clone()).or_default() += 1;
                    if let Some(code) = original["maps"]["map1"]["objects"][&p.id]["A"].as_str() {
                        *original_codes.entry(code.into()).or_default() += 1;
                    }
                } else {
                    runtime += 1;
                }
            }
            let original_enemies: u64 = original_codes
                .iter()
                .filter(|(k, _)| k.starts_with('e'))
                .map(|(_, v)| v)
                .sum();
            first_rows = serde_json::json!({"stepped_rows":session.stats().benchmark_stepped_source_rows.len(),"runtime_rows":runtime,"current_codes":current_codes,"original_codes":original_codes,"original_enemy_rows":original_enemies});
        }
        let detailed = tick == 1 || tick == ticks;
        for zoom in 0..=2 {
            let now = Instant::now();
            let (map, focus) = session.presentation_view();
            let region = scene.presentation_region(map, focus, [640.0, 480.0], zoom)?;
            let p = session.presentation_region(region);
            let picture = scene.picture(&p, [640.0, 480.0], zoom)?;
            let elapsed = now.elapsed().as_secs_f64() * 1000.0;
            let now = Instant::now();
            let full = session.presentation();
            let reference = scene.picture_before_spatial(&full, [640.0, 480.0], zoom)?;
            let reference_ms = now.elapsed().as_secs_f64() * 1000.0;
            if picture.world != reference.world
                || picture.hud != reference.hud
                || picture.tint != reference.tint
                || picture.entity_bounds_in_view != reference.entity_bounds_in_view
            {
                return Err(format!(
                    "early-cull output changed at tick={tick} zoom={zoom}"
                ));
            }
            if !detailed {
                continue;
            }
            let batch_count = |q: &[crate::gles::Quad]| {
                if q.is_empty() {
                    0
                } else {
                    1 + q
                        .windows(2)
                        .filter(|w| w[0].image != w[1].image || w[0].palette != w[1].palette)
                        .count()
                }
            };
            records.push(serde_json::json!({"saved_tick":p.tick,"zoom":zoom,"scale":picture.plan.scale,"scene_build_host_ms":elapsed,"reference_scene_build_host_ms":reference_ms,"reference_entities_art_built":reference.work.entities_art_built,"reference_work":reference.work,"render_index":session.render_index_metrics(),"collision_grid":session.world().maps[0].collision_grid_metrics(),"entities_bounds_in_view":picture.entity_bounds_in_view,"world_quads":picture.world.len(),"hud_quads":picture.hud.len(),"tint_quads":picture.tint.len(),"consecutive_batches":batch_count(&picture.world)+batch_count(&picture.tint)+batch_count(&picture.hud),"work":picture.work}));
        }
    }
    let report = serde_json::json!({"mode":"benchmark-only-headless-scene-work-no-GPU","level":args[0],"first_tick_row_classification":first_rows,"exact_quad_comparisons":ticks*3,"records":records,"scope":"actual scene::picture unchanged geometry; image dimensions/binary-alpha decoded exactly as upload; no GL calls, no GPU timing"});
    std::fs::write(
        &args[9],
        serde_json::to_vec_pretty(&report).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    println!(
        "HEADLESS_SCENE_WORK rows={} report={}",
        report["first_tick_row_classification"], args[9]
    );
    Ok(())
}

/// Host fill estimate: screen pixels each image covers in one 640x480 zoom-0 picture,
/// after the speed tool's walk-and-hop route. `--fill-host LEVEL COLLISION SCHEMA PACK
/// INVENTORY METRICS TICK`. Areas are axis-aligned quad boxes clipped to the screen.
pub fn fill_host(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    use crate::{pack::Pack, scene::Scene};
    use std::path::Path;
    let args: Vec<_> = arguments.collect();
    if args.len() != 7 {
        return Err("fill-host LEVEL COLLISION SCHEMA PACK INVENTORY METRICS TICK".into());
    }
    let read = |i: usize| std::fs::read_to_string(&args[i]).map_err(|e| e.to_string());
    let mut session = Session::load(&read(0)?, &read(1)?, &read(2)?).map_err(|e| e.to_string())?;
    let pack = Pack::open(Path::new(&args[3]), Path::new(&args[4]))?;
    let mut scene = Scene::prepare(
        session.world(),
        &session.admission_report().admitted_codes.clone(),
        &pack,
        Path::new(&args[5]),
    )?;
    scene.prepare_headless_assets(&pack)?;
    session.configure_presentation_index(scene.absolute_origin_guard());
    let mut cycle = Vec::new();
    for (n, m) in [
        (40, 2u8),
        (14, 6),
        (20, 2),
        (1, 8),
        (12, 0),
        (30, 2),
        (8, 0),
    ] {
        cycle.extend(std::iter::repeat_n(m, n));
    }
    let ticks: usize = args[6].parse().map_err(|_| "invalid tick")?;
    for i in 0..ticks {
        session
            .advance(cycle[i % cycle.len()])
            .map_err(|e| e.to_string())?;
    }
    let container = [640.0, 480.0];
    let (map_index, focus) = session.presentation_view();
    let region = scene.presentation_region(map_index, focus, container, 0)?;
    let p = session.presentation_region(region);
    let picture = scene.picture(&p, container, 0)?;
    let files = scene.image_files();
    let mut by: std::collections::BTreeMap<String, (f64, usize)> = Default::default();
    let mut total = 0.0;
    let mut quads = 0;
    for q in picture
        .world
        .iter()
        .chain(&picture.tint)
        .chain(&picture.hud)
    {
        let xs = q.corners.map(|c| c[0] as f64);
        let ys = q.corners.map(|c| c[1] as f64);
        let x0 = xs.iter().cloned().fold(f64::INFINITY, f64::min).max(0.0);
        let x1 = xs
            .iter()
            .cloned()
            .fold(f64::NEG_INFINITY, f64::max)
            .min(container[0]);
        let y0 = ys.iter().cloned().fold(f64::INFINITY, f64::min).max(0.0);
        let y1 = ys
            .iter()
            .cloned()
            .fold(f64::NEG_INFINITY, f64::max)
            .min(container[1]);
        let area = (x1 - x0).max(0.0) * (y1 - y0).max(0.0);
        let name = files
            .get(q.image)
            .cloned()
            .unwrap_or_else(|| format!("#generated{}", q.image - files.len()));
        let e = by.entry(name).or_default();
        e.0 += area;
        e.1 += 1;
        total += area;
        quads += 1;
    }
    let mut rows: Vec<_> = by.into_iter().collect();
    rows.sort_by(|a, b| b.1.0.total_cmp(&a.1.0));
    let screen = container[0] * container[1];
    println!(
        "HOST_FILL {}",
        serde_json::json!({"level":args[0],"tick":ticks,"scale":picture.plan.scale,"quads":quads,"screens_covered":total/screen,"top":rows.iter().take(10).map(|(n,(a,c))|serde_json::json!({"image":n,"screens":a/screen,"quads":c})).collect::<Vec<_>>()})
    );
    Ok(())
}

/// `--save-info LEVEL COLLISION SCHEMA SAVE`: a few saved fields of a snapshot (host).
pub fn save_info(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let args: Vec<_> = arguments.collect();
    if args.len() != 4 {
        return Err("save-info LEVEL COLLISION SCHEMA SAVE".into());
    }
    let read = |i: usize| std::fs::read_to_string(&args[i]).map_err(|e| e.to_string());
    let mut session = Session::load(&read(0)?, &read(1)?, &read(2)?).map_err(|e| e.to_string())?;
    session
        .restore(&std::fs::read(&args[3]).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    let p = session.presentation();
    let fields = ["goal_reached", "life_phase", "life_ticks", "frame"];
    let values: Vec<_> = fields
        .iter()
        .map(|f| format!("{f}={:?}", session.saved_field(f)))
        .collect();
    println!(
        "SAVE_INFO {} player_px=({:.1},{:.1}) status={:?} tick={}",
        values.join(" "),
        p.player.motion.current.x as f64 / eggshell_spike_core::SCALE as f64,
        p.player.motion.current.y as f64 / eggshell_spike_core::SCALE as f64,
        p.hud.status,
        p.tick
    );
    for step in 0..120 {
        session
            .advance(0)
            .map_err(|e| format!("step {step}: {e}"))?;
    }
    let q = session.presentation();
    println!(
        "SAVE_INFO_AFTER_120 tick={} player_px=({:.1},{:.1}) status={:?}",
        q.tick,
        q.player.motion.current.x as f64 / eggshell_spike_core::SCALE as f64,
        q.player.motion.current.y as f64 / eggshell_spike_core::SCALE as f64,
        q.hud.status
    );
    Ok(())
}

/// `--held-trace LEVEL COLLISION SCHEMA PACK INVENTORY METRICS INPUT`: per step, every
/// enemy row that is or was just held: its picture flags, position, animation, and how
/// many world quads the scene draws with and without it (host only).
pub fn held_trace(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    use crate::{pack::Pack, scene::Scene};
    use std::path::Path;
    let args: Vec<_> = arguments.collect();
    if args.len() != 7 {
        return Err("held-trace LEVEL COLLISION SCHEMA PACK INVENTORY METRICS INPUT".into());
    }
    let read = |i: usize| std::fs::read_to_string(&args[i]).map_err(|e| e.to_string());
    let mut session = Session::load(&read(0)?, &read(1)?, &read(2)?).map_err(|e| e.to_string())?;
    let pack = Pack::open(Path::new(&args[3]), Path::new(&args[4]))?;
    let mut scene = Scene::prepare(
        session.world(),
        &session.admission_report().admitted_codes.clone(),
        &pack,
        Path::new(&args[5]),
    )?;
    scene.prepare_headless_assets(&pack)?;
    session.configure_presentation_index(scene.absolute_origin_guard());
    let masks: Vec<u8> = serde_json::from_str(&read(6)?).map_err(|e| e.to_string())?;
    let container = [640.0, 480.0];
    let mut watched: std::collections::BTreeMap<i64, i64> = Default::default();
    for (i, mask) in masks.iter().enumerate() {
        session.advance(*mask).map_err(|e| e.to_string())?;
        // The game's autosave cadence: a snapshot every 60 accepted calls.
        if std::env::var_os("HELD_TRACE_SAVES").is_some() && (i + 1) % 60 == 0 {
            session.snapshot().map_err(|e| e.to_string())?;
        }
        let full = session.presentation();
        let (map_index, focus) = session.presentation_view();
        let region = scene.presentation_region(map_index, focus, container, 0)?;
        let p = session.presentation_region(region);
        for e in &full.entities {
            if e.held && !p.entities.iter().any(|r| r.token == e.token) {
                println!(
                    "HELD_TRACE_MISSING_FROM_REGION call={} token={}",
                    i + 1,
                    e.token
                );
            }
        }
        for e in &p.entities {
            if e.held {
                watched.insert(e.token, i as i64);
            }
        }
        for e in full
            .entities
            .iter()
            .filter(|e| watched.get(&e.token).is_some_and(|t| i as i64 - *t <= 40))
        {
            if !p.entities.iter().any(|r| r.token == e.token) {
                println!(
                    "HELD_TRACE_REGION_OMITS call={} token={} at=({:.1},{:.1}) region={region:?}",
                    i + 1,
                    e.token,
                    e.motion.current.x as f64 / eggshell_spike_core::SCALE as f64,
                    e.motion.current.y as f64 / eggshell_spike_core::SCALE as f64
                );
            }
        }
        let picture = scene.picture(&p, container, 0)?;
        for e in p
            .entities
            .iter()
            .filter(|e| watched.get(&e.token).is_some_and(|t| i as i64 - *t <= 40))
        {
            let mut without = p.clone();
            without.entities.retain(|o| o.token != e.token);
            let other = scene.picture(&without, container, 0)?;
            let own: Vec<_> = picture
                .world
                .iter()
                .filter(|q| !other.world.contains(q))
                .map(|q| {
                    format!(
                        "{}:{:?}:{:?}:{:?}",
                        scene
                            .image_files()
                            .get(q.image)
                            .cloned()
                            .unwrap_or_default(),
                        q.corners[0],
                        q.corners[2],
                        q.color
                    )
                })
                .collect();
            println!("HELD_TRACE_QUADS call={} {:?}", i + 1, own);
            println!(
                "HELD_TRACE call={} code={} token={} visible={} held={} hidden={} status={:?} at=({:.1},{:.1}) animation={:?} frame={:?} quads_for_row={} tongue={}",
                i + 1,
                e.code,
                e.token,
                e.visible,
                e.held,
                e.hidden,
                e.status,
                e.motion.current.x as f64 / eggshell_spike_core::SCALE as f64,
                e.motion.current.y as f64 / eggshell_spike_core::SCALE as f64,
                e.visual.animation,
                e.visual.frame,
                picture.world.len() as i64 - other.world.len() as i64,
                p.player.tongue.is_some()
            );
        }
    }
    Ok(())
}
