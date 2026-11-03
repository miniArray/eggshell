//! Optional lost-rider expression. All clocks advance on saved steps, never draws.
use crate::{
    binding::{Frame, Visual},
    geometry::{Transform, sprite_quad},
    gles::Quad,
    screen::Plan,
};
use eggshell_spike_core::{Lifetime, Presentation, SCALE};
use std::collections::VecDeque;

const HISTORY: usize = 2048;
const FLINCH_STEPS: i64 = 8;
const SEARCH_STEPS: i64 = 18;
// Reuse the pack's black outline and near-white highlight, with whole level pixels.
const INK: [f32; 4] = [0.0, 0.0, 0.0, 1.0];
const HIGHLIGHT: [f32; 4] = [248.0 / 255.0, 248.0 / 255.0, 248.0 / 255.0, 1.0];

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Sample {
    pub age: i64,
    phase: f64,
}
#[derive(Default)]
pub struct WorriedYoshi {
    last: Option<(i64, usize)>,
    start: Option<i64>,
    phase: f64,
    frames: VecDeque<(i64, Option<Sample>)>,
}
fn lost(mode: i64, lifetime: Lifetime) -> bool {
    // Mode 3 is the caught/return arc: stop immediately at rescue contact.
    [1, 2, 4].contains(&mode)
        && matches!(
            lifetime,
            Lifetime::Hurt | Lifetime::Separated | Lifetime::Active
        )
}
impl WorriedYoshi {
    pub fn observe(&mut self, p: &Presentation) {
        self.step(
            p.tick,
            p.map_index,
            lost(p.companions.mode, p.player.lifetime),
            p.player.velocity.x,
        );
    }
    fn step(&mut self, tick: i64, map: usize, active: bool, vx: i64) {
        if self.last == Some((tick, map)) {
            return;
        }
        if self
            .last
            .is_some_and(|(last, old_map)| tick != last + 1 || map != old_map)
        {
            *self = Self::default();
        }
        let sample = if active {
            let start = *self.start.get_or_insert(tick);
            self.phase += vx.unsigned_abs() as f64 / (SCALE as f64 * 8.0) * 1.75;
            Some(Sample {
                age: tick - start,
                phase: self.phase,
            })
        } else {
            self.start = None;
            self.phase = 0.0;
            None
        };
        self.frames.push_back((tick, sample));
        while self.frames.len() > HISTORY {
            self.frames.pop_front();
        }
        self.last = Some((tick, map));
    }
    pub fn sample(&self, p: &Presentation) -> Option<Sample> {
        if !lost(p.companions.mode, p.player.lifetime) {
            return None;
        }
        self.frames
            .iter()
            .rev()
            .find(|(tick, _)| *tick == p.tick)
            .and_then(|(_, sample)| *sample)
    }
}
fn idle(p: &Presentation) -> bool {
    p.player.on_floor
        && p.player.velocity.x == 0
        && ["Idle", "LookAround"]
            .iter()
            .any(|prefix| p.player.selected_pose.name.starts_with(prefix))
}
impl Sample {
    pub fn frame<'a>(
        &self,
        p: &Presentation,
        art: &'a Visual,
    ) -> Result<Option<&'a Frame>, String> {
        let pose = &p.player.selected_pose;
        let suffix = if pose.name.ends_with('1') { '1' } else { '0' };
        let name = if self.age < FLINCH_STEPS {
            format!("Hurt{suffix}")
        } else if idle(p) {
            format!(
                "{}{suffix}",
                if self.age / SEARCH_STEPS % 2 == 0 {
                    "LookAround"
                } else {
                    "IdleTurn"
                }
            )
        } else if ["Walk0", "Walk1", "Sprint0", "Sprint1"].contains(&pose.name.as_str()) {
            pose.name.clone()
        } else {
            return Ok(None);
        };
        let count = art
            .animations
            .iter()
            .find(|(n, _)| *n == name)
            .ok_or_else(|| format!("worried pose missing: {name}"))?
            .1
            .frames
            .len();
        let literal = if self.age < FLINCH_STEPS {
            0
        } else if idle(p) {
            (self.age / 2) % count as i64
        } else {
            self.phase as i64 % count as i64
        };
        art.sample_required(0, &name, 0, Some(literal)).map(Some)
    }
    pub fn offset(&self, p: &Presentation) -> f64 {
        if self.age >= FLINCH_STEPS && idle(p) {
            if self.age / 3 % 2 == 0 { -1.0 } else { 1.0 }
        } else {
            0.0
        }
    }
    pub fn cues(&self, body: [f64; 2], facing: i64, plan: &Plan, solid: usize) -> Vec<Quad> {
        let mut quads = Vec::new();
        let mut rect = |offset: [f64; 2], size: [f64; 2], color| {
            quads.push(sprite_quad(
                solid,
                [1.0; 2],
                Transform {
                    position: [body[0] + offset[0] * facing as f64, body[1] + offset[1]],
                    scale: [size[0] * facing as f64, size[1]],
                    ..Transform::default()
                },
                plan,
                color,
                &[],
            ));
        };
        if self.age < 20 {
            // Small outlined exclamation, only at separation; no enclosing UI panel.
            rect([2.0, -78.0], [5.0, 9.0], INK);
            rect([3.0, -77.0], [3.0, 4.0], HIGHLIGHT);
            rect([3.0, -71.0], [3.0, 1.0], HIGHLIGHT);
        }
        // A short, repeating falling sweat drop, not a time-based particle system.
        let phase = self.age % 48;
        if phase < 28 {
            let y = -50.0 + (phase / 7) as f64;
            rect([32.0, y], [1.0, 1.0], INK);
            rect([31.0, y + 1.0], [3.0, 2.0], INK);
            rect([30.0, y + 3.0], [5.0, 3.0], INK);
            rect([31.0, y + 6.0], [3.0, 1.0], INK);
            rect([32.0, y + 2.0], [1.0, 1.0], HIGHLIGHT);
            rect([31.0, y + 3.0], [3.0, 2.0], HIGHLIGHT);
        }
        quads
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn saved_steps_not_draws_drive_episode_and_panicky_cadence() {
        let mut clock = WorriedYoshi::default();
        for t in 0..100 {
            clock.step(t, 1, true, 4 * SCALE);
        }
        let sample = clock.frames.back().unwrap().1.unwrap();
        assert_eq!(sample.age, 99);
        assert_eq!(sample.phase, 87.5);
        clock.step(99, 1, true, 4 * SCALE);
        assert_eq!(clock.frames.back().unwrap().1, Some(sample));
        clock.step(100, 1, false, 0);
        assert!(clock.frames.back().unwrap().1.is_none());
        assert_eq!(clock.frames[99].1, Some(sample)); // pipeline can still draw preceding picture
        clock.step(101, 1, true, 0);
        assert_eq!(clock.frames.back().unwrap().1.unwrap().age, 0);
        clock.step(3, 1, true, 0);
        assert_eq!(clock.frames.back().unwrap().1.unwrap().age, 0);
        clock.step(4, 2, true, 0);
        assert_eq!(clock.frames.len(), 1);
        clock.step(10, 2, true, 0);
        assert_eq!(clock.frames.len(), 1);
    }
    #[test]
    fn caught_return_arc_and_death_stop_expression_immediately() {
        for mode in [1, 2, 4] {
            assert!(lost(mode, Lifetime::Separated));
        }
        for mode in [0, 3] {
            assert!(!lost(mode, Lifetime::Separated));
        }
        assert!(!lost(2, Lifetime::Dying));
        assert!(!lost(2, Lifetime::Respawning));
    }
}
