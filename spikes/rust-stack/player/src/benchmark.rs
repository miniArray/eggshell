//! Throwaway scaling hint. Never gameplay/correctness admission.
use eggshell_spike_core::Session;
use std::path::Path;

pub fn zoom_range(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let args: Vec<_> = arguments.collect();
    let real = args.get(2).is_some_and(|v| v == "real-screen");
    if args.len() != 2 && !real {
        return Err("--benchmark-zoom-range LEVEL COLLISION".into());
    }
    let level = std::fs::read_to_string(&args[0]).map_err(|e| e.to_string())?;
    let collision = std::fs::read_to_string(&args[1]).map_err(|e| e.to_string())?;
    let world = if real {
        eggshell_spike_core::World::compile_benchmark_real_screen(&level, &collision)
    } else {
        eggshell_spike_core::World::compile(&level, &collision)
    }
    .map_err(|e| e.to_string())?;
    let map = &world.maps[0];
    let p = crate::screen::plan(
        [640.0, 480.0],
        [map.width_pixels as f64, map.height_pixels as f64],
        [416.0, 224.0],
        1,
        0,
    )?;
    println!("RUST_ZOOM_RANGE {} {}", p.zoom_min, p.zoom_max);
    Ok(())
}
pub fn host_check(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let args: Vec<_> = arguments.collect();
    let real = args.get(4).is_some_and(|v| v == "real-screen");
    if args.len() != 4 && !real {
        return Err("benchmark host check requires LEVEL COLLISION SCHEMA TICKS".into());
    }
    let level = std::fs::read_to_string(Path::new(&args[0])).map_err(|e| e.to_string())?;
    let collision = std::fs::read_to_string(&args[1]).map_err(|e| e.to_string())?;
    let schema = std::fs::read_to_string(&args[2]).map_err(|e| e.to_string())?;
    let ticks = args[3].parse::<u64>().map_err(|e| e.to_string())?;
    if Session::load(&level, &collision, &schema).is_ok() {
        return Err("synthetic level unexpectedly passed strict fixture admission".into());
    }
    let load = if real {
        Session::load_benchmark_real_screen
    } else {
        Session::load_benchmark_unverified
    };
    let mut session = load(&level, &collision, &schema).map_err(|e| e.to_string())?;
    let mut changed: serde_json::Value = serde_json::from_str(&level).map_err(|e| e.to_string())?;
    let objects = changed["maps"]["map1"]["objects"]
        .as_object_mut()
        .ok_or("missing objects")?;
    objects.values_mut().next().ok_or("no entities")?["A"] =
        serde_json::json!("benchmark-unsupported-code");
    if load(&changed.to_string(), &collision, &schema).is_ok() {
        return Err("unsupported-code guard bypassed".into());
    }
    if load(&level, &format!("{collision} "), &schema).is_ok() {
        return Err("collision-hash guard bypassed".into());
    }
    let directory = std::env::temp_dir().join(format!(
        "owned-scaling-disabled-saves-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| e.to_string())?
            .as_nanos()
    ));
    let saves = crate::game::SavePipeline::start(directory.clone(), true);
    let mut save_samples = crate::timing::Samples::default();
    let map = &session.world().maps[0];
    let zoom_plan = crate::screen::plan(
        [640.0, 480.0],
        [map.width_pixels as f64, map.height_pixels as f64],
        [416.0, 224.0],
        1,
        0,
    )?;
    let initial = session.stats().entity_steps;
    let mut per_tick = Vec::new();
    let mut per_type_tick = Vec::new();
    let mut held = 0;
    for cursor in 1..=ticks {
        let before = session.stats().entity_steps;
        let type_before = session.benchmark_actor_steps();
        let frame = session.stats().tick;
        session.advance(0).map_err(|e| e.to_string())?;
        saves.cadence(&session, cursor, &mut save_samples)?;
        let _ = session.presentation();
        held += u64::from(session.stats().tick == frame);
        per_tick.push(session.stats().entity_steps - before);
        if let (Some(a), Some(b)) = (type_before, session.benchmark_actor_steps()) {
            per_type_tick.push(std::array::from_fn::<u64, 5, _>(|i| b[i] - a[i]));
        }
    }
    saves.manual(&session, &mut save_samples)?;
    let writes = saves.finish(&session, &mut save_samples)?;
    if writes != 0 || save_samples.wall.count != 0 || directory.exists() {
        return Err("benchmark shared save path encoded/wrote unexpectedly".into());
    }
    let total = session.stats().entity_steps - initial;
    println!(
        "OWNED_SCALING_HOST_CHECK {}",
        serde_json::json!({"benchmark_unverified_level":true,"saves_disabled":true,"scale":zoom_plan.scale,"zoom":zoom_plan.zoom,"zoom_min":zoom_plan.zoom_min,"zoom_max":zoom_plan.zoom_max,"save_writes":writes,"shared_player_save_hooks_exercised":["start-before-ready","per-tick-cadence","manual","final"],"level":args[0],"placed_rows":session.admission_report().placed_rows,"idle_calls":ticks,"startup_entity_steps":initial,"active_entity_steps":total,"active_entity_steps_per_call":total as f64/ticks as f64,"per_tick_entity_steps":per_tick,"actor_type_order":["e1","e2","e3","e5","e35"],"actual_debug_dispatch_steps_per_type_per_tick":per_type_tick,"dispatch_instrumentation_in_release":false,"saved_frame":session.stats().tick,"held_saved_frame_calls":held,"strict_identity_refused":true,"unsupported_code_refused":true,"collision_hash_refused":true,"hint_only":true})
    );
    Ok(())
}
