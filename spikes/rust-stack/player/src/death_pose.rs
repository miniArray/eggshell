//! Drawing-only death poses and fade, observed on successful saved steps.
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
    fn episode(&self, tick: i64) -> Option<(i64, bool)> {
        self.start.filter(|(start, _)| *start <= tick).or_else(|| {
            self.finished
                .filter(|(start, end, _)| (*start..*end).contains(&tick))
                .map(|(start, _, lava)| (start, lava))
        })
    }
    pub fn fade(&self, tick: i64, lifetime: Lifetime) -> f32 {
        if lifetime != Lifetime::Dying {
            return 0.0;
        }
        self.episode(tick).map_or(0.0, |(start, _)| {
            ((tick - start - 240) as f32 / 60.0).clamp(0.0, 1.0)
        })
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
            let start = self.episode(tick);
            if let Some((start, true)) = start {
                let age = tick.saturating_sub(start);
                // The launch has a short hold, a rising frame, then a falling frame.
                // Position stays core-owned; this adapter only selects the picture.
                let frame = i64::from((15..48).contains(&age));
                let name = if pose.name.ends_with('1') {
                    "Hurt1"
                } else {
                    "Hurt0"
                };
                if art.animations.iter().any(|(bound, _)| bound == name) {
                    return art.sample_required(0, name, 0, Some(frame));
                }
            }
            if let Some((start, false)) = start {
                let age = tick.saturating_sub(start);
                if age < 156 && art.animations.iter().any(|(name, _)| name == "Spin") {
                    return art.sample_required(0, "Spin", 0, Some(slowing_spin_frame(age)));
                }
            }
            // For wet actions the suffix denotes water, not a full mouth. The DTO
            // has no separate full-mouth flag; use Defeat0 in those ambiguous poses.
            let full = pose.name.ends_with('1')
                && !["Tongue", "Spit", "Spew"]
                    .iter()
                    .any(|prefix| pose.name.starts_with(prefix));
            let name = if full { "Defeat1" } else { "Defeat0" };
            if let Some((start, _)) = start
                && art.animations.iter().any(|(bound, _)| bound == name)
            {
                return art.sample_required(tick.saturating_sub(start + 156), name, 0, None);
            }
        }
        art.sample_required(pose.tick, &pose.name, pose.frame, literal)
    }
}

/// Frame duration changes with the current speed, rather than integrating speed
/// into a phase. This matters near the end: the final spin frame holds for 36 steps.
fn slowing_spin_frame(age: i64) -> i64 {
    let mut frame = 0;
    let mut start = 0.0;
    for step in 24..=age.min(155) {
        let time = (step - 23) as f64;
        let speed = 24.0 * (1.0 - (step - 24) as f64 / 132.0);
        let duration = 60.0 / speed;
        if time >= start + duration {
            frame = (frame + 1) % 6;
            start += duration;
            if time > start + duration {
                start = time;
            }
        }
    }
    frame
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
    #[test]
    fn impact_spin_frame_schedule_includes_hold_and_slowdown() {
        let changes = [
            (0, 0),
            (26, 1),
            (29, 2),
            (31, 3),
            (34, 4),
            (37, 5),
            (40, 0),
            (42, 1),
            (45, 2),
            (49, 3),
            (52, 4),
            (55, 5),
            (58, 0),
            (62, 1),
            (65, 2),
            (69, 3),
            (73, 4),
            (77, 5),
            (82, 0),
            (87, 1),
            (92, 2),
            (97, 3),
            (104, 4),
            (111, 5),
            (120, 0),
        ];
        for age in 0..156 {
            let expected = changes
                .iter()
                .rev()
                .find(|(start, _)| *start <= age)
                .unwrap()
                .1;
            assert_eq!(slowing_spin_frame(age), expected, "impact age {age}");
        }
    }
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
        if defeat {
            animations["Spin"] = serde_json::json!({"fps":24,"loop":true,"frames":
                (0..6).map(|i| serde_json::json!({"file":format!("spin-{i}.png")})).collect::<Vec<_>>()});
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
    fn lava_uses_hurt_frames_not_spin_and_fades_at_the_end() {
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
        let art = Catalog::default()
            .visual(
                &serde_json::json!({"animations":{
                    "Hurt0":{"fps":0,"frames":[{"file":"hurt0.png"},{"file":"hurt1.png"}]},
                    "Defeat0":{"fps":24,"loop":false,"frames":[{"file":"defeat.png"}]}
                }}),
                0,
                1,
                false,
            )
            .unwrap();
        let pose = PoseSelection {
            name: "Fall0".into(),
            tick: 100,
            frame: 0,
        };
        let mut clock = DeathPose::default();
        clock.observe_step(100, Lifetime::Dying, true);
        for age in 0..=300 {
            clock.observe_step(100 + age, Lifetime::Dying, false);
            assert_eq!(
                clock.fade(100 + age, Lifetime::Dying),
                ((age - 240) as f32 / 60.0).clamp(0.0, 1.0)
            );
            assert_eq!(
                clock
                    .frame(100 + age, Lifetime::Dying, &pose, &art, None)
                    .unwrap(),
                art.sample(0, "Hurt0", 0, Some(i64::from((15..48).contains(&age))))
            );
        }
        clock.observe_step(401, Lifetime::Respawning, false);
        assert_eq!(
            clock
                .frame(399, Lifetime::Dying, &pose, &art, None)
                .unwrap(),
            art.sample(0, "Hurt0", 0, Some(0))
        );
        clock.observe_step(410, Lifetime::Dying, false);
        clock.observe_step(411, Lifetime::Dying, true);
        assert_eq!(
            clock
                .frame(411, Lifetime::Dying, &pose, &art, None)
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
        let first = art.sample(0, "Defeat0", 0, None).image;
        for (age, frame) in [
            (156, 0),
            (158, 0),
            (159, 1),
            (161, 2),
            (164, 3),
            (166, 4),
            (240, 4),
        ] {
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
            art.sample(0, "Spin", 0, Some(0)).image
        );
        clock.observe_step(100, Lifetime::Dying, false); // Restore: start a new local episode.
        assert_eq!(
            clock
                .frame(100, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            art.sample(0, "Spin", 0, Some(0)).image
        );
        let full = PoseSelection {
            name: "Fall1".into(),
            ..pose
        };
        assert_eq!(
            clock
                .frame(100, Lifetime::Dying, &full, &art, None)
                .unwrap(),
            art.sample(0, "Spin", 0, Some(0))
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
            art.sample(0, "Spin", 0, Some(0))
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
