//! Host-only position-adapter probe. Input/output traces and pack paths stay private.
use eggshell_spike_player::egg_trail::{EggTrail, TrailStep};
use serde::Deserialize;
#[derive(Deserialize)]
struct Row {
    step: TrailStep,
    expected: Vec<[f64; 2]>,
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() != 2 {
        return Err("egg_trace_probe PRIVATE_INPUT.json PRIVATE_OUTPUT.json".into());
    }
    let rows: Vec<Row> = serde_json::from_slice(&std::fs::read(&args[0])?)?;
    let mut trail = EggTrail::default();
    let mut out = Vec::new();
    for row in rows {
        let s = &row.step;
        if s.count > 6 || !valid_step(s) || row.expected.len() != s.count {
            return Err(format!("invalid trace row at {}", s.tick).into());
        }
        let actual = trail.advance(s);
        out.push(serde_json::json!({"tick":s.tick,"actual":actual,"expected":row.expected}));
    }
    std::fs::write(&args[1], serde_json::to_vec(&out)?)?;
    println!(
        "EGG_TRACE_PROBE rows={} output_written=true adapter_only=true",
        out.len()
    );
    Ok(())
}
fn valid_step(s: &TrailStep) -> bool {
    s.player
        .iter()
        .chain(&s.grab)
        .chain(s.hand.iter().flatten())
        .chain(s.pickups.iter().flatten())
        .all(|v| v.is_finite())
        && s.map != 0
        && [-1, 1].contains(&s.facing)
}
