//! Deterministic pixel bursts, derived only from read-only per-step presentations.
//! Observe every step, not just drawn frames: a whole landing can occur between draws.
use crate::feel::FeelSettings;
use eggshell_spike_core::{Lifetime, Presentation, SCALE};

const LIFE: i64 = 24;
// Small fixed muted palette; solid squares need no pack art.
const PALETTE: [[f32; 4]; 4] = [
    [0.58, 0.54, 0.46, 1.0],
    [0.70, 0.66, 0.57, 1.0],
    [0.63, 0.62, 0.59, 1.0],
    [0.80, 0.72, 0.59, 1.0],
];
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    Landing,
    Pound,
    Hit,
}
#[derive(Clone, Copy)]
struct Sample {
    tick: i64,
    map: usize,
    at: [f64; 2],
    feet: f64,
    center: f64,
    floor: bool,
    action: i64,
    hurt: bool,
}
impl From<&Presentation> for Sample {
    fn from(p: &Presentation) -> Self {
        Self {
            tick: p.tick,
            map: p.map_index,
            at: [
                p.player.motion.current.x as f64 / SCALE as f64,
                p.player.motion.current.y as f64 / SCALE as f64,
            ],
            feet: p.player.body_bounds[3] as f64 / SCALE as f64,
            center: (p.player.body_bounds[1] + p.player.body_bounds[3]) as f64
                / (2.0 * SCALE as f64),
            floor: p.player.on_floor,
            action: p.player.action,
            hurt: p.player.lifetime == Lifetime::Hurt,
        }
    }
}
struct Burst {
    tick: i64,
    map: usize,
    at: [f64; 2],
    kind: Kind,
    amount: i64,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Particle {
    pub rect: [f64; 4],
    pub color: [f32; 4],
}
#[derive(Default)]
pub struct Dust {
    previous: Option<Sample>,
    bursts: Vec<Burst>,
}
impl Dust {
    pub fn observe(&mut self, p: &Presentation, settings: FeelSettings) {
        self.observe_sample(p.into(), settings);
    }
    fn observe_sample(&mut self, s: Sample, settings: FeelSettings) {
        if let Some(last) = self.previous {
            if s.tick < last.tick || s.map != last.map {
                self.bursts.clear();
            } else if s.tick > last.tick && settings.dust_enabled && settings.dust_amount > 0 {
                let pound =
                    (s.action == 3 && last.action != 3) || (last.action == 2 && s.action != 2);
                if pound || (!last.floor && s.floor) {
                    self.bursts.push(Burst {
                        tick: s.tick,
                        map: s.map,
                        at: [s.at[0], s.at[1] + s.feet],
                        kind: if pound { Kind::Pound } else { Kind::Landing },
                        amount: settings.dust_amount,
                    });
                }
                if s.hurt && !last.hurt {
                    self.bursts.push(Burst {
                        tick: s.tick,
                        map: s.map,
                        at: [s.at[0], s.at[1] + s.center],
                        kind: Kind::Hit,
                        amount: settings.dust_amount,
                    });
                }
            }
        }
        // Repeated observations do not create edges.
        self.previous = Some(s);
    }
    /// Sampling never consumes future bursts: the pipeline can observe ahead of drawing.
    pub fn particles(&mut self, tick: i64, map: usize, settings: FeelSettings) -> Vec<Particle> {
        self.bursts.retain(|b| tick - b.tick < LIFE);
        if !settings.dust_enabled || settings.dust_amount == 0 {
            return Vec::new();
        }
        let mut out = Vec::new();
        for b in &self.bursts {
            let age = tick - b.tick;
            if !(0..LIFE).contains(&age) || b.map != map {
                continue;
            }
            let count = b.amount.min(settings.dust_amount)
                * match b.kind {
                    Kind::Landing => 3,
                    Kind::Pound => 5,
                    Kind::Hit => 4,
                };
            for i in 0..count {
                let seed = hash((b.tick as u64).wrapping_mul(977).wrapping_add(i as u64));
                let t = age as f64;
                let side = if i % 2 == 0 { -1.0 } else { 1.0 };
                let speed = 0.35 + (seed % 11) as f64 / 15.0;
                let (vx, vy) = if b.kind == Kind::Hit {
                    let angle = (seed % 360) as f64 * std::f64::consts::PI / 180.0;
                    (angle.cos() * 1.6, angle.sin() * 1.6)
                } else {
                    (
                        side * speed * if b.kind == Kind::Pound { 1.5 } else { 1.0 },
                        -0.7 - ((seed >> 8) % 10) as f64 / 12.0,
                    )
                };
                let size = if age < 10 { 2.0 } else { 1.0 };
                let mut color = PALETTE[(seed as usize) % PALETTE.len()];
                color[3] = 1.0 - age as f32 / LIFE as f32;
                out.push(Particle {
                    rect: [
                        (b.at[0] + vx * t).round(),
                        (b.at[1] + vy * t + 0.035 * t * t).round(),
                        size,
                        size,
                    ],
                    color,
                });
            }
        }
        out
    }
}
fn hash(mut x: u64) -> u64 {
    x = x.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    x ^= x >> 31;
    x = x.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x ^ (x >> 29)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample(tick: i64, floor: bool, action: i64, hurt: bool) -> Sample {
        Sample {
            tick,
            map: 1,
            at: [100.0, 100.0],
            feet: 0.0,
            center: -28.0,
            floor,
            action,
            hurt,
        }
    }
    #[test]
    fn landing_pound_hit_decay_repeat_and_restore() {
        let s = FeelSettings::default();
        let mut d = Dust::default();
        d.observe_sample(sample(10, false, 0, false), s);
        d.observe_sample(sample(11, true, 0, false), s);
        let first = d.particles(11, 1, s);
        assert_eq!(first.len(), 6);
        d.observe_sample(sample(11, true, 0, false), s);
        assert_eq!(first, d.particles(11, 1, s));
        let later = d.particles(20, 1, s);
        assert_eq!(later.len(), 6);
        assert!(later[0].color[3] < first[0].color[3]);
        assert!(d.particles(35, 1, s).is_empty());
        d.observe_sample(sample(36, false, 2, false), s);
        d.observe_sample(sample(37, true, 3, false), s);
        assert_eq!(d.particles(37, 1, s).len(), 10);
        d.observe_sample(sample(38, true, 0, true), s);
        assert_eq!(d.particles(38, 1, s).len(), 18);
        d.observe_sample(sample(5, true, 0, false), s);
        assert!(d.particles(5, 1, s).is_empty());
    }
    #[test]
    fn skipped_draws_keep_short_landing_and_hit_and_do_not_show_future_events() {
        let s = FeelSettings::default();
        let mut d = Dust::default();
        d.observe_sample(sample(10, false, 0, false), s);
        d.observe_sample(sample(11, true, 0, false), s);
        d.observe_sample(sample(12, false, 0, true), s);
        d.observe_sample(sample(13, false, 0, false), s);
        assert!(d.particles(10, 1, s).is_empty());
        assert_eq!(d.particles(13, 1, s).len(), 14);
        // Same event history, regardless of which frames were drawn.
        let mut every = Dust::default();
        for step in [
            sample(10, false, 0, false),
            sample(11, true, 0, false),
            sample(12, false, 0, true),
            sample(13, false, 0, false),
        ] {
            every.observe_sample(step, s);
            every.particles(step.tick, 1, s);
        }
        assert_eq!(d.particles(13, 1, s), every.particles(13, 1, s));
    }
    #[test]
    fn disabled_zero_amount_and_map_change_suppress_particles() {
        let s = FeelSettings::default();
        let mut d = Dust::default();
        d.observe_sample(sample(10, false, 2, false), s);
        d.observe_sample(sample(13, true, 0, false), s);
        assert_eq!(d.particles(13, 1, s).len(), 10); // POUND_LAND not observed.
        assert!(
            d.particles(
                13,
                1,
                FeelSettings {
                    dust_enabled: false,
                    ..s
                }
            )
            .is_empty()
        );
        assert!(
            d.particles(
                13,
                1,
                FeelSettings {
                    dust_amount: 0,
                    ..s
                }
            )
            .is_empty()
        );
        let mut next = sample(14, true, 0, false);
        next.map = 2;
        d.observe_sample(next, s);
        assert!(d.particles(14, 2, s).is_empty());
    }
}
