use eggshell_spike_core::Session;
use eggshell_spike_player::{
    audio::{AudioMap, Observer},
    dust::Dust,
    feel::FeelSettings,
    goal_music::Proximity,
};
fn main() {
    let collision = include_str!("../../../../data/collision_table.json");
    let schema_path = std::env::args()
        .nth(1)
        .expect("usage: cargo run --example feel_probe -- SCHEMA.json");
    let schema = std::fs::read_to_string(schema_path).unwrap();
    for (name, level) in [
        (
            "collections",
            include_str!("../../core/tests/fixtures/collections.level.json"),
        ),
        (
            "lagoon",
            include_str!("../../../../tests/fixtures/lagoon.level.json"),
        ),
    ] {
        let mut on = Session::load(level, collision, &schema).unwrap();
        let mut off = Session::load(level, collision, &schema).unwrap();
        let settings = FeelSettings::default();
        let disabled = FeelSettings {
            shake_enabled: false,
            dust_enabled: false,
            muffle_enabled: false,
            sparkle_enabled: false,
            splash_enabled: false,
            goal_music_enabled: false,
            ..settings
        };
        let mut dust = Dust::default();
        let mut no_dust = Dust::default();
        let mut audio = Observer::new(AudioMap::default(), on.world(), None, None).unwrap();
        let mut goal = Proximity::new(on.world());
        let mut bursts = 0;
        let mut swimming_edges = 0;
        let mut pickups = 0;
        let mut max_goal = 0.0_f32;
        let mut prev = on.presentation();
        dust.observe(&prev, settings, &on.world().maps[0]);
        no_dust.observe(&prev, disabled, &off.world().maps[0]);
        for _ in 0..400 {
            on.advance(2).unwrap();
            off.advance(2).unwrap();
            let p = on.presentation_region([0; 4]);
            let snapshot = on.snapshot().unwrap();
            dust.observe(&p, settings, &on.world().maps[0]);
            audio.observe(&on);
            audio.observe_feel(&p, settings);
            max_goal = max_goal.max(goal.observe(&p, settings));
            if p.sound.serial > prev.sound.serial && p.sound.kind == 2 {
                pickups += 1;
            }
            if p.player.swimming != prev.player.swimming {
                swimming_edges += 1;
            }
            if !dust.particles(p.tick, p.map_index, settings).is_empty() {
                bursts += 1;
            }
            no_dust.observe(&p, disabled, &off.world().maps[0]);
            assert!(no_dust.particles(p.tick, p.map_index, disabled).is_empty());
            assert_eq!(on.snapshot().unwrap(), snapshot, "observer wrote state");
            assert_eq!(
                snapshot,
                off.snapshot().unwrap(),
                "settings changed snapshot"
            );
            prev = p;
        }
        assert!(bursts > 0);
        if name == "collections" {
            assert_eq!(pickups, 4);
            assert!(max_goal > 0.2);
        }
        if name == "lagoon" {
            assert!(swimming_edges > 0);
        }
        let bytes = on.snapshot().unwrap();
        on.restore(&bytes).unwrap();
        audio.replaced();
        let p = on.presentation_region([0; 4]);
        audio.observe_feel(&p, settings);
        assert_eq!(on.snapshot().unwrap(), bytes);
        println!(
            "FEEL_PROBE level={name} steps=400 pickups={pickups} swimming_edges={swimming_edges} particle_frames={bursts} max_goal_amount={max_goal:.3} save_bytes_identical=true"
        );
    }
}
