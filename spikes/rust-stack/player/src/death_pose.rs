//! Spike presentation deviation: core and player_pose.gd do not select death art.
//! Start the pack's non-looping Defeat animation on the first observed Dying step.
//! This invented clock never changes core state, camera, collision or visibility.
use crate::binding::{Frame, Visual};
use eggshell_spike_core::{Lifetime, PoseSelection, Presentation};

#[derive(Default)]
pub struct DeathPose {
    last_tick: Option<i64>,
    start: Option<i64>,
    // One pipelined frame can still be drawing when the worker observes respawn.
    finished: Option<(i64, i64)>,
}
impl DeathPose {
    pub fn observe(&mut self, p: &Presentation) {
        self.observe_step(p.tick, p.player.lifetime);
    }
    fn observe_step(&mut self, tick: i64, lifetime: Lifetime) {
        if self.last_tick.is_some_and(|last| tick < last) {
            *self = Self::default();
        }
        if lifetime == Lifetime::Dying {
            self.start.get_or_insert(tick);
        } else if let Some(start) = self.start.take() {
            self.finished = Some((start, tick));
        }
        self.last_tick = Some(tick);
    }
    pub fn frame<'a>(
        &self,
        tick: i64,
        lifetime: Lifetime,
        pose: &PoseSelection,
        art: &'a Visual,
        literal: Option<usize>,
    ) -> Result<&'a Frame, String> {
        if lifetime == Lifetime::Dying {
            let start = self.start.filter(|start| *start <= tick).or_else(|| {
                self.finished
                    .filter(|(start, end)| (*start..*end).contains(&tick))
                    .map(|(start, _)| start)
            });
            // For wet actions the suffix denotes water, not a full mouth. The DTO
            // has no separate full-mouth flag; use Defeat0 in those ambiguous poses.
            let full = pose.name.ends_with('1')
                && !["Tongue", "Spit", "Spew"]
                    .iter()
                    .any(|prefix| pose.name.starts_with(prefix));
            let name = if full { "Defeat1" } else { "Defeat0" };
            if let Some(start) = start
                && art.animations.iter().any(|(bound, _)| bound == name)
            {
                return art.sample_required(tick.saturating_sub(start), name, 0, None);
            }
        }
        art.sample_required(pose.tick, &pose.name, pose.frame, literal)
    }
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
    fn death_clock_uses_saved_steps_24fps_holds_and_resets() {
        let art = fixture_art(true);
        let pose = PoseSelection {
            name: "Fall0".into(),
            tick: 900,
            frame: 0,
        };
        let mut clock = DeathPose::default();
        clock.observe_step(100, Lifetime::Active);
        clock.observe_step(101, Lifetime::Dying);
        let first = clock
            .frame(101, Lifetime::Dying, &pose, &art, None)
            .unwrap()
            .image;
        for (age, frame) in [(0, 0), (2, 0), (3, 1), (5, 2), (8, 3), (10, 4), (240, 4)] {
            clock.observe_step(101 + age, Lifetime::Dying);
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
        clock.observe_step(342, Lifetime::Respawning);
        assert_eq!(
            clock.frame(342, Lifetime::Respawning, &pose, &art, None).unwrap(),
            art.sample(0, "Fall0", 0, None)
        );
        assert_eq!(
            clock
                .frame(341, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            first + 4
        );
        clock.observe_step(400, Lifetime::Dying);
        assert_eq!(
            clock
                .frame(400, Lifetime::Dying, &pose, &art, None)
                .unwrap()
                .image,
            first
        );
        clock.observe_step(100, Lifetime::Dying); // Restore: start a new local episode.
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
            clock.frame(100, Lifetime::Dying, &full, &art, None).unwrap(),
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
            clock.observe_step(tick, Lifetime::Dying);
        }
        let art = fixture_art(true);
        assert_eq!(
            clock.frame(206, Lifetime::Dying, &pose, &art, None).unwrap(),
            art.sample(6, "Defeat0", 0, None)
        );
        let missing = fixture_art(false);
        assert_eq!(
            clock.frame(206, Lifetime::Dying, &pose, &missing, None).unwrap(),
            missing.sample(300, "Fall0", 0, None)
        );
    }
}
