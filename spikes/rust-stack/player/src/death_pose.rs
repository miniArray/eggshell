//! Spike presentation deviation: core and player_pose.gd do not select death art.
//! Lava contact at the first Dying step selects looping Spin; other deaths use Defeat.
//! This invented clock never changes core state, camera, collision or visibility.
use crate::binding::{Frame, Visual};
use eggshell_spike_core::{Lifetime, Map, PoseSelection, Presentation, SCALE, TerrainHazard};

#[derive(Default)]
pub struct DeathPose {
    last_tick: Option<i64>,
    start: Option<(i64, bool)>,
    // One pipelined frame can still be drawing when the worker observes respawn.
    finished: Option<(i64, i64, bool)>,
}
impl DeathPose {
    pub fn observe(&mut self, p: &Presentation, map: &Map) {
        if self.last_tick.is_some_and(|last| p.tick < last) {
            *self = Self::default();
        }
        let lava =
            p.player.lifetime == Lifetime::Dying && self.start.is_none() && touches_lava(p, map);
        self.observe_step(p.tick, p.player.lifetime, lava);
    }
    fn observe_step(&mut self, tick: i64, lifetime: Lifetime, lava: bool) {
        if self.last_tick.is_some_and(|last| tick < last) {
            *self = Self::default();
        }
        if lifetime == Lifetime::Dying {
            self.start.get_or_insert((tick, lava));
        } else if let Some((start, lava)) = self.start.take() {
            self.finished = Some((start, tick, lava));
        }
        self.last_tick = Some(tick);
    }
    pub fn frame<'a>(
        &self,
        tick: i64,
        lifetime: Lifetime,
        pose: &PoseSelection,
        art: &'a Visual,
        literal: Option<i64>,
    ) -> Result<&'a Frame, String> {
        if lifetime == Lifetime::Dying {
            let start = self.start.filter(|(start, _)| *start <= tick).or_else(|| {
                self.finished
                    .filter(|(start, end, _)| (*start..*end).contains(&tick))
                    .map(|(start, _, lava)| (start, lava))
            });
            // For wet actions the suffix denotes water, not a full mouth. The DTO
            // has no separate full-mouth flag; use Defeat0 in those ambiguous poses.
            let full = pose.name.ends_with('1')
                && !["Tongue", "Spit", "Spew"]
                    .iter()
                    .any(|prefix| pose.name.starts_with(prefix));
            let name = if start.is_some_and(|(_, lava)| lava) {
                "Spin"
            } else if full {
                "Defeat1"
            } else {
                "Defeat0"
            };
            if let Some((start, _)) = start
                && art.animations.iter().any(|(bound, _)| bound == name)
            {
                return art.sample_required(tick.saturating_sub(start), name, 0, None);
            }
        }
        art.sample_required(pose.tick, &pose.name, pose.frame, literal)
    }
}

/// Cell coverage is presentation-only. Read just the player's occupied tile range.
fn touches_lava(p: &Presentation, map: &Map) -> bool {
    let at = p.player.motion.current;
    let b = p.player.body_bounds;
    let bounds = [at.x + b[0], at.y + b[1], at.x + b[2], at.y + b[3]];
    lava_in_bounds(bounds, map)
}
fn lava_in_bounds(bounds: [i64; 4], map: &Map) -> bool {
    if bounds[2] < 0 || bounds[3] < 0 {
        return false;
    }
    map.layers
        .iter()
        .filter(|l| l.hazard == TerrainHazard::Lava)
        .any(|l| {
            let size = l.tile_size_pixels * SCALE;
            let left = bounds[0].div_euclid(size).max(0) as usize;
            let top = bounds[1].div_euclid(size).max(0) as usize;
            let right = bounds[2].div_euclid(size).max(0) as usize;
            let bottom = bounds[3].div_euclid(size).max(0) as usize;
            (top..=bottom.min(l.height.saturating_sub(1))).any(|y| {
                (left..=right.min(l.width.saturating_sub(1)))
                    .any(|x| l.cells.get(y * l.width + x).is_some_and(|c| *c != -1))
            })
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::binding::Catalog;
    fn fixture_art(defeat: bool) -> Visual {
        let mut animations = serde_json::json!({"Fall0":{"fps":0,"frames":[{"file":"fall.png"}]}});
        if defeat {
            for name in ["Defeat0", "Defeat1"] {
                animations[name] = serde_json::json!({"fps":24,"loop":false,"frames":[
                    {"file":format!("{name}-0.png")},{"file":format!("{name}-1.png")},
                    {"file":format!("{name}-2.png")},{"file":format!("{name}-3.png")},{"file":format!("{name}-4.png")}
                ]});
            }
        }
        Catalog::default()
            .visual(
                &serde_json::json!({"animations":animations,"default_animation":"Fall0"}),
                0,
                1,
                false,
            )
            .unwrap()
    }
    #[test]
    fn lava_uses_compiled_cells_and_spin_is_locked_for_the_episode() {
        let world = eggshell_spike_core::World::compile(
            include_str!("../tests/fixtures/lighting.level.json"),
            include_str!("../../../../src/level/collision_table.json"),
        )
        .unwrap();
        let map = &world.maps[0];
        let layer = map
            .layers
            .iter()
            .find(|l| l.hazard == TerrainHazard::Lava)
            .unwrap();
        let cell = layer.cells.iter().position(|c| *c != -1).unwrap();
        let x = (cell % layer.width) as i64 * layer.tile_size_pixels * SCALE;
        let y = (cell / layer.width) as i64 * layer.tile_size_pixels * SCALE;
        assert!(lava_in_bounds([x, y - 50 * SCALE, x + 10 * SCALE, y], map));
        assert!(!lava_in_bounds(
            [x, y - 50 * SCALE, x + 10 * SCALE, y - 1],
            map
        ));
        let art = Catalog::default().visual(&serde_json::json!({"animations":{
            "Spin":{"fps":24,"loop":true,"frames":[{"file":"0.png"},{"file":"1.png"},{"file":"2.png"},{"file":"3.png"},{"file":"4.png"},{"file":"5.png"}]},
            "Defeat0":{"fps":24,"loop":false,"frames":[{"file":"defeat.png"}]}
        }}),0,1,false).unwrap();
        let pose = PoseSelection {
            name: "Fall0".into(),
            tick: 100,
            frame: 0,
        };
        let mut clock = DeathPose::default();
        clock.observe_step(100, Lifetime::Dying, true);
        for age in 0..60 {
            clock.observe_step(100 + age, Lifetime::Dying, false);
            assert_eq!(
                clock
                    .frame(100 + age, Lifetime::Dying, &pose, &art, None)
                    .unwrap(),
                art.sample(age, "Spin", 0, None)
            );
        }
        clock.observe_step(160, Lifetime::Respawning, false);
        assert_eq!(
            clock
                .frame(159, Lifetime::Dying, &pose, &art, None)
                .unwrap(),
            art.sample(59, "Spin", 0, None)
        );
        clock.observe_step(170, Lifetime::Dying, false);
        clock.observe_step(171, Lifetime::Dying, true);
        assert_eq!(
            clock
                .frame(171, Lifetime::Dying, &pose, &art, None)
                .unwrap(),
            art.sample(1, "Defeat0", 0, None)
        );
    }
    #[test]
    fn death_clock_uses_saved_steps_24fps_holds_and_resets() {
        let art = fixture_art(true);
        let pose = PoseSelection {
            name: "Fall0".into(),
            tick: 900,
            frame: 0,
        };
        let mut clock = DeathPose::default();
        clock.observe_step(100, Lifetime::Active, false);
        clock.observe_step(101, Lifetime::Dying, false);
        let first = clock
            .frame(101, Lifetime::Dying, &pose, &art, None)
            .unwrap()
            .image;
        for (age, frame) in [(0, 0), (2, 0), (3, 1), (5, 2), (8, 3), (10, 4), (240, 4)] {
            clock.observe_step(101 + age, Lifetime::Dying, false);
            assert_eq!(
                clock
                    .frame(101 + age, Lifetime::Dying, &pose, &art, None)
                    .unwrap()
                    .image,
                first + frame
            );
        }
        // Repeated draws/pauses and a phase 2→3 transition do not restart the clock.
        assert_eq!(
            clock
                .frame(341, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            first + 4
        );
        clock.observe_step(342, Lifetime::Respawning, false);
        assert_eq!(
            clock
                .frame(342, Lifetime::Respawning, &pose, &art, None)
                .unwrap(),
            art.sample(0, "Fall0", 0, None)
        );
        assert_eq!(
            clock
                .frame(341, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            first + 4
        );
        clock.observe_step(400, Lifetime::Dying, false);
        assert_eq!(
            clock
                .frame(400, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            first
        );
        clock.observe_step(100, Lifetime::Dying, false); // Restore: start a new local episode.
        assert_eq!(
            clock
                .frame(100, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            first
        );
        let full = PoseSelection {
            name: "Fall1".into(),
            ..pose
        };
        assert_eq!(
            clock
                .frame(100, Lifetime::Dying, &full, &art, None)
                .unwrap(),
            art.sample(0, "Defeat1", 0, None)
        );
    }
    #[test]
    fn every_step_observation_preserves_start_across_skipped_draws_and_missing_art_falls_back() {
        let pose = PoseSelection {
            name: "Fall0".into(),
            tick: 300,
            frame: 0,
        };
        let mut clock = DeathPose::default();
        for tick in 200..=206 {
            clock.observe_step(tick, Lifetime::Dying, false);
        }
        let art = fixture_art(true);
        assert_eq!(
            clock
                .frame(206, Lifetime::Dying, &pose, &art, None)
                .unwrap(),
            art.sample(6, "Defeat0", 0, None)
        );
        let missing = fixture_art(false);
        assert_eq!(
            clock
                .frame(206, Lifetime::Dying, &pose, &missing, None)
                .unwrap(),
            missing.sample(300, "Fall0", 0, None)
        );
    }
}
