//! Host-only real Session tongue path; drawing observes but cannot alter snapshots.
use eggshell_spike_core::{SCALE, Session};
use eggshell_spike_player::{
    elastic_tongue::{ElasticTongue, point},
    input,
};
fn main() {
    let schema =
        std::fs::read_to_string(std::env::args().nth(1).expect("tongue_probe SCHEMA.json"))
            .unwrap();
    let level = include_str!("../../core/tests/fixtures/collections.level.json");
    let mut session = Session::load(
        level,
        include_str!("../../../../src/level/collision_table.json"),
        &schema,
    )
    .unwrap();
    let mut curve = ElasticTongue::default();
    let mut seen = 0;
    let mut bent = 0;
    let mut airborne = [0; 3];
    for step in 0..480 {
        let phase = step % 90;
        let mask = input::RIGHT
            | if step % 36 < 12 { input::USE } else { 0 }
            | if step > 30 && phase < 75 && !(30..33).contains(&phase) {
                input::JUMP
            } else {
                0
            };
        session.advance(mask).unwrap();
        let before = session.snapshot().unwrap();
        let p = session.presentation();
        curve.observe(&p);
        if let Some(tongue) = p.player.tongue {
            let mouth = [
                (p.player.motion.current.x + tongue.mouth[0]) as f64 / SCALE as f64,
                (p.player.motion.current.y + tongue.mouth[1]) as f64 / SCALE as f64,
            ];
            let length = tongue.length as f64 / SCALE as f64;
            let tip = if tongue.up {
                [mouth[0], mouth[1] - length]
            } else {
                [mouth[0] + p.player.facing as f64 * length, mouth[1]]
            };
            let bend = curve.bend(p.tick, p.map_index, length);
            assert_eq!(point(mouth, tip, bend, 0.0), mouth);
            assert_eq!(point(mouth, tip, bend, 1.0), tip);
            if !p.player.on_floor {
                assert_eq!(bend, [0.0; 2], "air tongue must stay straight");
                airborne[0] += usize::from(p.player.velocity.y < 0);
                airborne[1] += usize::from(p.player.velocity.y > 0);
                airborne[2] +=
                    usize::from(session.saved_field("flutter_remaining").unwrap_or(0) > 0);
            }
            seen += 1;
            bent += usize::from(bend != [0.0; 2]);
        }
        assert_eq!(session.snapshot().unwrap(), before);
    }
    assert!(seen > 0 && bent > 0);
    assert!(
        airborne.iter().all(|n| *n > 0),
        "ascending/falling/fluttering coverage {airborne:?}"
    );
    println!(
        "TONGUE_PROBE steps=480 ascending_falling_fluttering={airborne:?} tongue_steps={seen} bent_steps={bent} endpoints_exact=true snapshots_unchanged=true"
    );
}
