//! Host-only investigation: real Session input on a three-tile pool, no core edits.
use eggshell_spike_core::{SCALE, Session};
use serde_json::json;

fn pool(schema: &str, capped: bool) -> Session {
    let mut cells = vec![-1; 20 * 15];
    for row in 9..12 {
        for column in 4..16 {
            cells[row * 20 + column] = i32::from(capped && row != 9);
        }
    }
    let water = json!({"c2tilemap":true,"width":20,"height":15,
        "data":cells.iter().map(ToString::to_string).collect::<Vec<_>>().join(",")});
    let mut layer = json!({"castle32":"{\"c2tilemap\":true,\"width\":20,\"height\":15,\"data\":\"240x-1,60x0\"}"});
    layer[if capped { "water3" } else { "water" }] = water.to_string().into();
    let level = json!({"version":"1","name":"Water jump investigation","desc":"Host investigation only","author":"Eggshell",
        "startpoint":{"map":1,"X":320,"Y":384},"flowers":0,"redcoins":0,
        "maps":{"map1":{"width":640,"height":480,"objects":{},"layer1":layer,"layer2":{},"bgcolor":"0,0,0"}}});
    Session::load_benchmark_unverified(
        &level.to_string(),
        include_str!("../../../../src/level/collision_table.json"),
        schema,
    )
    .unwrap()
}
fn main() {
    let schema =
        std::fs::read_to_string(std::env::args().nth(1).expect("water_probe SCHEMA.json")).unwrap();
    for capped in [false, true] {
        let name = if capped { "water3" } else { "water" };
        let mut held = pool(&schema, capped);
        for _ in 0..180 {
            held.advance(4).unwrap();
        }
        let surface = held.presentation();
        assert!(surface.player.swimming);
        assert_ne!(surface.player.selected_pose.name, "Jump0");
        println!(
            "WATER_PROBE tilemap={name} held_from_deep=180 swimming=true feet_y={:.3} pose={}",
            surface.player.motion.current.y as f64 / SCALE as f64,
            surface.player.selected_pose.name
        );
        held.advance(0).unwrap(); // A release creates a new edge on the next step.
        let start = held.presentation().tick;
        let mut exited = None;
        for age in 1..=30 {
            held.advance(4).unwrap();
            let p = held.presentation();
            if age == 1 {
                assert_eq!(p.player.velocity.y, -776 * 60);
                assert_eq!(p.player.selected_pose.name, "Jump0");
            }
            if !p.player.swimming {
                exited = Some((age, p.player.motion.current.y));
                break;
            }
        }
        let (age, y) = exited.expect("fresh jump held at surface must leave water");
        println!(
            "WATER_PROBE tilemap={name} fresh_press_at_tick={} exited_after_steps={age} feet_y={:.3}",
            start + 1,
            y as f64 / SCALE as f64
        );

        let mut idle = pool(&schema, capped);
        for _ in 0..180 {
            idle.advance(0).unwrap();
        }
        assert!(idle.presentation().player.swimming);
        idle.advance(4).unwrap();
        assert_eq!(idle.presentation().player.velocity.y, -776 * 60);
        let mut tap_exit = None;
        for age in 2..=61 {
            idle.advance(0).unwrap(); // One-step tap: release cuts rising velocity to 1/4.
            if !idle.presentation().player.swimming {
                tap_exit.get_or_insert(age);
            }
        }
        println!("WATER_PROBE tilemap={name} one_step_tap_exit_after_steps={tap_exit:?}");
    }
}
