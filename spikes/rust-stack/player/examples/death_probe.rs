//! Host-only investigation through the public Session/Presentation and pack binding.
use eggshell_spike_core::{Lifetime, Session};
use eggshell_spike_player::binding::Catalog;
use std::collections::BTreeSet;

fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    assert_eq!(args.len(), 2, "death_probe SCHEMA.json PACK_MANIFEST.json");
    let schema = std::fs::read_to_string(&args[0]).unwrap();
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&args[1]).unwrap()).unwrap();
    assert_eq!(
        eggshell_spike_player::pack::hash(&std::fs::read(&args[1]).unwrap()),
        eggshell_spike_player::pack::MANIFEST_SHA
    );
    let art = Catalog::default()
        .visual(
            &serde_json::json!({"animations":manifest["player"],"default_animation":"Idle0"}),
            0,
            1,
            false,
        )
        .unwrap();
    let death_names: Vec<_> = art
        .animations
        .iter()
        .filter(|(name, _)| {
            let name = name.to_lowercase();
            name.contains("dead")
                || name.contains("death")
                || name.contains("die")
                || name.contains("defeat")
        })
        .map(|(name, _)| name.as_str())
        .collect();
    println!("DEATH_PROBE pack_death_names={death_names:?}");
    for (impact, mode) in [
        (false, eggshell_spike_player::feel::LavaDeath::Original),
        (false, eggshell_spike_player::feel::LavaDeath::Spin),
        (true, eggshell_spike_player::feel::LavaDeath::Spin),
    ] {
        let mut level: serde_json::Value =
            serde_json::from_str(include_str!("../tests/fixtures/lighting.level.json")).unwrap();
        // Start on the fixture's lava. No saved state or core internals are changed.
        level["startpoint"]["X"] = 400.into();
        level["maps"]["map1"]["objects"] = serde_json::json!({});
        if impact {
            level["startpoint"]["X"] = 128.into();
            level["startpoint"]["Y"] = 384.into();
            level["maps"]["map1"]["layer1"]["castle32"] = serde_json::json!(
                "{\"c2tilemap\":true,\"width\":20,\"height\":15,\"data\":\"240x-1,60x0\"}"
            );
            level["maps"]["map1"]["layer2"] = serde_json::json!({});
            level["maps"]["map1"]["objects"] = serde_json::json!({"0":{"A":"o12","X":192,"Y":368}});
        }
        let mut session = Session::load_benchmark_unverified(
            &level.to_string(),
            include_str!("../../../../data/collision_table.json"),
            &schema,
        )
        .unwrap();
        let mut death = eggshell_spike_player::death_pose::DeathPose::default();
        let mut rendered = BTreeSet::new();
        let mut phases = BTreeSet::new();
        let mut poses = BTreeSet::new();
        for call in 1..=310 {
            session
                .advance(if impact && call <= 30 { 2 } else { 0 })
                .unwrap();
            let p = session.presentation();
            death.observe(&p, &session.world().maps[p.map_index - 1]);
            if p.player.lifetime == Lifetime::Dying {
                let pose = &p.player.selected_pose;
                let frame = art
                    .sample_required(pose.tick, &pose.name, pose.frame, None)
                    .unwrap();
                poses.insert(pose.name.clone());
                rendered.insert(
                    death
                        .frame(p.tick, p.player.lifetime, pose, &art, None, mode)
                        .unwrap()
                        .image,
                );
                assert!(p.player.visible);
                assert_eq!(p.player.visual.alpha, 1.0);
                if phases.insert(p.player.life_phase) {
                    println!(
                        "DEATH_PROBE call={call} tick={} lifetime={:?} phase={} visible={} pose={pose:?} frame_image={} position={:?} follow={:?}",
                        p.tick,
                        p.player.lifetime,
                        p.player.life_phase,
                        p.player.visible,
                        frame.image,
                        p.player.motion.current,
                        p.follow.current
                    );
                }
            }
        }
        assert_eq!(phases, BTreeSet::from([2, 3]));
        assert_eq!(
            rendered.len(),
            if impact || mode == eggshell_spike_player::feel::LavaDeath::Spin {
                11
            } else {
                2
            }
        );
        println!(
            "DEATH_PROBE impact={impact} mode={mode:?} rendered_death_frames={} dying_poses={poses:?} required_bindings_resolve=true hidden=false",
            rendered.len()
        );
    }
}
