//! Host-only held-item presentation check through real Session input.
use eggshell_spike_core::{SCALE, Session};
use eggshell_spike_player::held_melons::{HeldMelons, pulled};
fn main() {
    let schema =
        std::fs::read_to_string(std::env::args().nth(1).expect("melon_probe SCHEMA")).unwrap();
    for form in [4, 6] {
        let level = serde_json::json!({"version":"1","name":"Held item check","desc":"Host only","author":"Eggshell",
            "startpoint":{"map":1,"X":64,"Y":384},"flowers":0,"redcoins":0,
            "maps":{"map1":{"width":640,"height":480,"objects":{"item":{"A":"o25","X":140,"Y":368,"F":form}},
            "layer1":{"castle32":"{\"c2tilemap\":true,\"width\":20,\"height\":15,\"data\":\"240x-1,60x0\"}"},"layer2":{},"bgcolor":"0,0,0"}}});
        let mut session = Session::load_benchmark_unverified(
            &level.to_string(),
            include_str!("../../../../data/collision_table.json"),
            &schema,
        )
        .unwrap();
        let mut holds = HeldMelons::default();
        let mut held_ticks = 0;
        let mut tip_x = vec![];
        for tick in 0..60 {
            session.advance(if tick < 20 { 8 } else { 0 }).unwrap();
            let before = session.snapshot().unwrap();
            holds.observe(&session);
            let p = session.presentation();
            let tip = p.player.tongue.map(|t| eggshell_spike_core::Position {
                x: p.player.motion.current.x + t.mouth[0] + p.player.facing * t.length,
                y: p.player.motion.current.y + t.mouth[1],
            });
            for e in &p.entities {
                if let Some(drawn) = pulled(e, tip, holds.tokens(p.tick, p.map_index)) {
                    assert!(drawn.visible && !drawn.held);
                    assert_eq!(drawn.motion.current, tip.unwrap());
                    held_ticks += 1;
                    tip_x.push(drawn.motion.current.x as f64 / SCALE as f64);
                }
            }
            assert_eq!(session.snapshot().unwrap(), before);
        }
        assert!(held_ticks > 1);
        assert!(tip_x.windows(2).any(|v| v[1] < v[0]));
        assert!(holds.tokens(session.stats().tick, 1).is_empty());
        println!(
            "MELON_PROBE form={form} held_draw_steps={held_ticks} positions_x={tip_x:?} snapshots_unchanged=true"
        );
    }
}
