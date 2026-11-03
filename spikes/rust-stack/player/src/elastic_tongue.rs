//! Drawing-only tongue lag. Saved-step observations, never wall-clock animation.
use crate::geometry::Patch;
use eggshell_spike_core::{Presentation, SCALE};

#[derive(Clone, Copy)]
struct Sample {
    tick: i64,
    map: usize,
    lag: [f64; 2],
}
#[derive(Default)]
pub struct ElasticTongue {
    current: Option<Sample>,
    previous: Option<Sample>,
}
impl ElasticTongue {
    pub fn observe(&mut self, p: &Presentation) {
        self.step(
            p.tick,
            p.map_index,
            p.player.tongue.is_some() && p.player.on_floor && !p.player.swimming,
            [
                p.player.velocity.x as f64 / SCALE as f64,
                p.player.velocity.y as f64 / SCALE as f64,
            ],
        );
    }
    fn step(&mut self, tick: i64, map: usize, out: bool, velocity: [f64; 2]) {
        if self.current.is_some_and(|s| s.tick == tick && s.map == map) {
            return;
        }
        let old = self.current.filter(|s| s.map == map && s.tick + 1 == tick);
        let mut lag = [0.0; 2];
        if out {
            // Three steps of trailing motion, eased by 1/4 each simulation step.
            // A small downward bow also makes motion along the tongue visible.
            let target = [
                -velocity[0] * 3.0,
                -velocity[1] * 3.0 + velocity[0].abs() * 0.4,
            ];
            for axis in 0..2 {
                let from = old.map_or(0.0, |s| s.lag[axis]);
                lag[axis] = from + (target[axis].clamp(-24.0, 24.0) - from) * 0.25;
            }
        }
        self.previous = old;
        self.current = Some(Sample { tick, map, lag });
    }
    pub fn bend(&self, tick: i64, map: usize, length: f64) -> [f64; 2] {
        self.current
            .filter(|s| s.tick == tick && s.map == map)
            .or_else(|| self.previous.filter(|s| s.tick == tick && s.map == map))
            .map_or([0.0; 2], |s| {
                s.lag.map(|v| v.clamp(-length * 0.35, length * 0.35))
            })
    }
}

/// Quadratic Bézier: control point is the midpoint plus lag. Endpoints are exact.
pub fn point(mouth: [f64; 2], tip: [f64; 2], bend: [f64; 2], t: f64) -> [f64; 2] {
    if t == 0.0 {
        return mouth;
    }
    if t == 1.0 {
        return tip;
    }
    std::array::from_fn(|axis| {
        mouth[axis] + (tip[axis] - mouth[axis]) * t + 2.0 * t * (1.0 - t) * bend[axis]
    })
}

/// Keep nine-patch caps and UVs. Split stretched/tiled body bands into <=8-pixel
/// segments so each quad follows the curve rather than spanning the whole tongue.
pub fn segments(patches: Vec<Patch>, up: bool, unit: f64) -> Vec<Patch> {
    let axis = usize::from(up);
    let mut result = Vec::new();
    for patch in patches {
        let count = (patch.destination[axis + 2] * unit / 8.0).ceil().max(1.0) as usize;
        for i in 0..count {
            let mut part = patch;
            part.destination[axis] += patch.destination[axis + 2] * i as f64 / count as f64;
            part.source[axis] += patch.source[axis + 2] * i as f64 / count as f64;
            part.destination[axis + 2] /= count as f64;
            part.source[axis + 2] /= count as f64;
            result.push(part);
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn endpoints_exact_lag_eases_and_repeated_draws_do_not_advance() {
        let mut clock = ElasticTongue::default();
        for tick in 1..=8 {
            clock.step(tick, 1, true, [4.0, -2.0]);
        }
        let bend = clock.bend(8, 1, 100.0);
        assert!(bend[0] < -10.0 && bend[1] > 6.0);
        for (mouth, tip) in [
            ([50.0, 50.0], [150.0, 50.0]),
            ([50.0, 50.0], [-50.0, 50.0]),
            ([50.0, 50.0], [50.0, -50.0]),
        ] {
            assert_eq!(point(mouth, tip, bend, 0.0), mouth);
            assert_eq!(point(mouth, tip, bend, 1.0), tip);
            assert_ne!(
                point(mouth, tip, bend, 0.5),
                point(mouth, tip, [0.0; 2], 0.5)
            );
        }
        clock.step(8, 1, true, [100.0; 2]);
        assert_eq!(clock.bend(8, 1, 100.0), bend);
        clock.step(9, 1, true, [0.0; 2]);
        assert_eq!(clock.bend(8, 1, 100.0), bend); // pipelined old frame
        assert_eq!(clock.bend(9, 1, 100.0), bend.map(|v| v * 0.75));
        clock.step(2, 1, false, [0.0; 2]); // restore
        assert_eq!(clock.bend(2, 1, 100.0), [0.0; 2]);
        clock.step(3, 2, false, [0.0; 2]);
        assert_eq!(clock.bend(3, 2, 100.0), [0.0; 2]);
    }
    #[test]
    fn leaving_ground_discards_the_bend_instead_of_dragging_air_tongues() {
        let mut clock = ElasticTongue::default();
        clock.step(1, 1, true, [4.0, 0.0]);
        assert_ne!(clock.bend(1, 1, 100.0), [0.0; 2]);
        // The observer gates deformation to a grounded, non-swimming tongue.
        for (tick, velocity) in [(2, [4.0, -12.0]), (3, [4.0, 12.0]), (4, [4.0, -1.0])] {
            clock.step(tick, 1, false, velocity);
            assert_eq!(clock.bend(tick, 1, 100.0), [0.0; 2]);
        }
    }
    #[test]
    fn segmented_art_keeps_source_coverage_and_shared_edges() {
        for up in [false, true] {
            let patch = Patch {
                source: [2.0, 3.0, 4.0, 6.0],
                destination: [0.0, 0.0, 40.0, 48.0],
            };
            let parts = segments(vec![patch], up, 1.0);
            let a = usize::from(up);
            assert!(parts.iter().all(|p| p.destination[a + 2] <= 8.0));
            assert_eq!(
                parts.iter().map(|p| p.source[a + 2]).sum::<f64>(),
                patch.source[a + 2]
            );
            for pair in parts.windows(2) {
                assert!(
                    (pair[0].destination[a] + pair[0].destination[a + 2] - pair[1].destination[a])
                        .abs()
                        < 1e-9
                );
            }
        }
    }
}
