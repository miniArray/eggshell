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
pub struct WorriedPlayer {
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
impl WorriedPlayer {
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
        // Pixel glyph dimensions replace the old 5x9 / 5x7 cues; no pack sprite exists.
        const EXCLAMATION: &[[f64; 4]] = &[[0.0, 0.0, 6.0, 10.0], [0.0, 14.0, 6.0, 2.0]];
        const SWEAT: &[[f64; 4]] = &[
            [4.0, 0.0, 2.0, 2.0],
            [2.0, 2.0, 6.0, 4.0],
            [0.0, 6.0, 10.0, 6.0],
            [2.0, 12.0, 6.0, 2.0],
        ];
        // One short separation pop. Quantize the scaled edges, not the outline width.
        let (scale, bounce) = match self.age {
            0 => (0.75, 0.0),
            1 => (1.0, -2.0),
            2..=3 => (1.25, -4.0),
            4..=5 => (1.125, -2.0),
            _ => (1.0, 0.0),
        };
        let body = body.map(crate::screen::godot_round);
        let mut quads = Vec::new();
        let mut glyph = |anchor: [f64; 2], shape: &[[f64; 4]]| {
            let rects = shape
                .iter()
                .map(|[x, y, w, h]| {
                    [x * scale, y * scale, (x + w) * scale, (y + h) * scale]
                        .map(crate::screen::godot_round)
                })
                .collect::<Vec<_>>();
            // Stroke the whole silhouette first, then fill it: no dark internal seams.
            for (pad, color) in [(1.0, INK), (0.0, HIGHLIGHT)] {
                for [left, top, right, bottom] in &rects {
                    quads.push(sprite_quad(
                        solid,
                        [1.0; 2],
                        Transform {
                            position: [
                                body[0] + (anchor[0] + left - pad) * facing as f64,
                                body[1] + anchor[1] + top - pad + bounce,
                            ],
                            scale: [
                                (right - left + 2.0 * pad) * facing as f64,
                                bottom - top + 2.0 * pad,
                            ],
                            ..Transform::default()
                        },
                        plan,
                        color,
                        &[],
                    ));
                }
            }
        };
        if self.age < 20 {
            glyph([3.0, -87.0], EXCLAMATION);
        }
        // Keep the existing 48-step falling-drop cycle; only separation gets the pop.
        let phase = self.age % 48;
        if phase < 28 {
            glyph([27.0, -54.0 + (phase / 7) as f64], SWEAT);
        }
        quads
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn native_cues(age: i64, facing: i64) -> Vec<Quad> {
        let plan =
            crate::screen::plan([640.0, 480.0], [640.0, 480.0], [320.0, 240.0], 1, 0).unwrap();
        Sample { age, phase: 0.0 }.cues([320.25, 240.25], facing, &plan, 0)
    }
    fn exclamation_bounds(age: i64) -> [f32; 4] {
        let corners = native_cues(age, 1)
            .into_iter()
            .filter(|q| q.corners[0][1] < 175.0)
            .flat_map(|q| q.corners)
            .collect::<Vec<_>>();
        [
            corners.iter().map(|p| p[0]).fold(f32::INFINITY, f32::min),
            corners.iter().map(|p| p[1]).fold(f32::INFINITY, f32::min),
            corners
                .iter()
                .map(|p| p[0])
                .fold(f32::NEG_INFINITY, f32::max),
            corners
                .iter()
                .map(|p| p[1])
                .fold(f32::NEG_INFINITY, f32::max),
        ]
    }
    #[test]
    fn cues_double_native_size_and_keep_exactly_one_pixel_outline_and_grid() {
        let bounds = exclamation_bounds(8);
        assert_eq!([bounds[2] - bounds[0], bounds[3] - bounds[1]], [8.0, 18.0]);
        for facing in [-1, 1] {
            let quads = native_cues(8, facing);
            let mut pixels = std::collections::BTreeMap::new();
            for q in &quads {
                for [x, y] in q.corners {
                    assert_eq!(x.fract(), 0.0);
                    assert_eq!(y.fract(), 0.0);
                }
                let left = q.corners.iter().map(|p| p[0] as i32).min().unwrap();
                let right = q.corners.iter().map(|p| p[0] as i32).max().unwrap();
                for y in q.corners[0][1] as i32..q.corners[2][1] as i32 {
                    for x in left..right {
                        pixels.insert((x, y), q.color);
                    }
                }
            }
            // Every highlight has an unbroken outline, and no ink is thicker than one pixel.
            for (&(x, y), &color) in &pixels {
                if color == HIGHLIGHT {
                    for dx in -1..=1 {
                        for dy in -1..=1 {
                            assert!(
                                pixels.contains_key(&(x + dx, y + dy)),
                                "open outline at {x},{y}"
                            );
                        }
                    }
                } else {
                    assert!(
                        (-1..=1).any(|dx| (-1..=1)
                            .any(|dy| pixels.get(&(x + dx, y + dy)) == Some(&HIGHLIGHT))),
                        "thick outline at {x},{y}"
                    );
                }
            }
            let drop = pixels
                .keys()
                .filter(|(_, y)| *y > 175)
                .copied()
                .collect::<Vec<_>>();
            assert_eq!(
                drop.iter().map(|p| p.0).max().unwrap() - drop.iter().map(|p| p.0).min().unwrap()
                    + 1,
                12
            );
            assert_eq!(
                drop.iter().map(|p| p.1).max().unwrap() - drop.iter().map(|p| p.1).min().unwrap()
                    + 1,
                16
            );
        }
    }
    #[test]
    fn pop_and_facing_keep_level_pixel_edges_at_each_zoom() {
        for zoom in [0.0, 0.25, 1.0] {
            let plan =
                crate::screen::plan([640.0, 480.0], [2048.0, 448.0], [800.0, 224.0], 1, zoom)
                    .unwrap();
            for facing in [-1, 1] {
                for age in 0..20 {
                    let quads = Sample { age, phase: 0.0 }.cues([800.25, 300.75], facing, &plan, 0);
                    for q in quads {
                        for corner in q.corners {
                            for (axis, value) in corner.iter().enumerate() {
                                let level = (f64::from(*value)
                                    - crate::screen::godot_round(plan.offset[axis]))
                                    / plan.scale;
                                assert_eq!(
                                    level.fract(),
                                    0.0,
                                    "age={age} facing={facing} zoom={zoom}"
                                );
                            }
                        }
                    }
                }
            }
        }
    }
    #[test]
    fn separation_pop_grows_overshoots_and_settles_in_six_saved_steps() {
        let size = |age| {
            let b = exclamation_bounds(age);
            [b[2] - b[0], b[3] - b[1]]
        };
        assert!(size(0)[1] < size(2)[1]);
        assert!(size(2)[1] > size(6)[1]);
        assert_eq!(exclamation_bounds(6), exclamation_bounds(19));
        assert_eq!(native_cues(2, 1), native_cues(2, 1));
        assert!(native_cues(28, 1).is_empty());
    }
    #[test]
    fn saved_steps_not_draws_drive_episode_and_panicky_cadence() {
        let mut clock = WorriedPlayer::default();
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
