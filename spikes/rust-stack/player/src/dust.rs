//! Deterministic pixel bursts, derived only from read-only per-step presentations.
//! Observe every step, not just drawn frames: a whole landing can occur between draws.
use crate::feel::FeelSettings;
use eggshell_spike_core::{Lifetime, Map, Presentation, SCALE};

const LIFE: i64 = 28;
// Small fixed muted palette; solid squares need no pack art.
// Light dust tones so the puffs read against dark terrain and backgrounds.
const PALETTE: [[f32; 4]; 4] = [
    [0.93, 0.90, 0.82, 1.0],
    [0.86, 0.82, 0.72, 1.0],
    [0.98, 0.96, 0.90, 1.0],
    [0.80, 0.76, 0.68, 1.0],
];
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    Landing,
    Pound,
    Hit,
    Sparkle,
    Splash,
}
impl Kind {
    fn life(self) -> i64 {
        match self {
            Self::Sparkle => 16,
            Self::Splash => 24,
            _ => LIFE,
        }
    }
    fn enabled(self, settings: FeelSettings) -> bool {
        match self {
            Self::Sparkle => settings.sparkle_enabled,
            Self::Splash => settings.splash_enabled,
            _ => settings.dust_enabled && settings.dust_amount > 0,
        }
    }
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
    pickup_serial: i64,
    pickup: Option<[f64; 2]>,
    swimming: bool,
    vy: f64,
    surface: Option<f64>,
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
            swimming: p.player.swimming,
            vy: p.player.velocity.y as f64 / SCALE as f64,
            surface: None,
            pickup_serial: p.sound.serial,
            // Core emits sound kind 2 only on coin/red coin/flower/star collection,
            // including tongue collection and stars at the 30-health cap. Unlike
            // disappearing pictures or HUD increases, this cannot mean despawn or healing.
            pickup: (p.sound.kind == 2).then_some([
                p.sound.position.x as f64 / SCALE as f64,
                p.sound.position.y as f64 / SCALE as f64,
            ]),
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
    pub fn observe(&mut self, p: &Presentation, settings: FeelSettings, map: &Map) {
        let mut s = Sample::from(p);
        if settings.splash_enabled
            && self.previous.is_some_and(|last| {
                last.map == s.map && s.tick > last.tick && last.swimming != s.swimming
            })
        {
            // Swimming starts at the core's upper-body probe, not the feet.
            let probe = if s.swimming {
                if s.floor { 42.0 } else { 66.0 }
            } else {
                0.0
            };
            s.surface = water_surface(map, s.at[0], s.at[1] - probe);
        }
        self.observe_sample(s, settings);
    }
    fn observe_sample(&mut self, s: Sample, settings: FeelSettings) {
        if let Some(last) = self.previous {
            if s.tick < last.tick || s.map != last.map {
                self.bursts.clear();
            } else if s.tick > last.tick {
                if settings.splash_enabled
                    && last.swimming != s.swimming
                    && let Some(y) = s.surface
                {
                    self.bursts.push(Burst {
                        tick: s.tick,
                        map: s.map,
                        at: [s.at[0], y],
                        kind: Kind::Splash,
                        // Buoyancy can zero the entry velocity in this very step.
                        amount: (s.vy.abs().max(last.vy.abs()) / 4.0)
                            .floor()
                            .clamp(0.0, 2.0) as i64
                            + 1,
                    });
                }
                if settings.sparkle_enabled
                    && s.pickup_serial > last.pickup_serial
                    && let Some(at) = s.pickup
                {
                    self.bursts.push(Burst {
                        tick: s.tick,
                        map: s.map,
                        at,
                        kind: Kind::Sparkle,
                        amount: 1,
                    });
                }
                if settings.dust_enabled && settings.dust_amount > 0 {
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
        }
        // Repeated observations do not create edges.
        self.previous = Some(s);
    }
    /// Sampling never consumes future bursts: the pipeline can observe ahead of drawing.
    pub fn particles(&mut self, tick: i64, map: usize, settings: FeelSettings) -> Vec<Particle> {
        self.bursts.retain(|b| tick - b.tick < b.kind.life());
        let mut out = Vec::new();
        for b in &self.bursts {
            let age = tick - b.tick;
            if !(0..b.kind.life()).contains(&age) || b.map != map || !b.kind.enabled(settings) {
                continue;
            }
            let count = if b.kind == Kind::Sparkle {
                4 + (hash(b.tick as u64) % 3) as i64
            } else if b.kind == Kind::Splash {
                6 + b.amount * 2
            } else {
                b.amount.min(settings.dust_amount)
                    * match b.kind {
                        Kind::Landing => 4,
                        Kind::Pound => 8,
                        Kind::Hit => 6,
                        Kind::Sparkle | Kind::Splash => unreachable!(),
                    }
            };
            for i in 0..count {
                let seed = hash((b.tick as u64).wrapping_mul(977).wrapping_add(i as u64));
                let t = age as f64;
                let side = if i % 2 == 0 { -1.0 } else { 1.0 };
                // Fast enough to leave the player's sprite within a few steps.
                let speed = 0.9 + (seed % 11) as f64 / 10.0;
                if b.kind == Kind::Sparkle {
                    let angle = (i as f64 / count as f64 * 360.0 + (seed % 25) as f64).to_radians();
                    let radius = 5.0 + t * 0.8;
                    let size = if (age + i * 3) % 6 < 3 { 3.0 } else { 1.0 };
                    // Requested yellow/white twinkle; no matching pack art is needed.
                    let mut color = if i % 2 == 0 {
                        [1.0, 0.91, 0.22, 1.0]
                    } else {
                        [1.0; 4]
                    };
                    color[3] = 1.0 - age as f32 / b.kind.life() as f32;
                    out.push(Particle {
                        rect: [
                            (b.at[0] + angle.cos() * radius - size / 2.0).round(),
                            (b.at[1] + angle.sin() * radius - size / 2.0).round(),
                            size,
                            size,
                        ],
                        color,
                    });
                    continue;
                }
                if b.kind == Kind::Splash {
                    let spread = i as f64 / (count - 1) as f64 * 2.0 - 1.0;
                    let power = 1.0 + b.amount as f64 * 0.4;
                    let vx = spread * power * 1.5;
                    let vy = -(1.4 + (1.0 - spread.abs()) * 1.8) * power;
                    let size = if i % 3 == 0 { 3.0 } else { 2.0 };
                    // Requested pale blue/white droplets, on the existing solid-quad layer.
                    let mut color = if i % 3 == 0 {
                        [1.0; 4]
                    } else {
                        [0.65, 0.86, 1.0, 1.0]
                    };
                    color[3] = 1.0 - age as f32 / b.kind.life() as f32;
                    out.push(Particle {
                        rect: [
                            (b.at[0] + vx * t - size / 2.0).round(),
                            (b.at[1] + vy * t + 0.16 * t * t - size).round(),
                            size,
                            size,
                        ],
                        color,
                    });
                    continue;
                }
                let (vx, vy) = if b.kind == Kind::Hit {
                    let angle = (seed % 360) as f64 * std::f64::consts::PI / 180.0;
                    (angle.cos() * 2.2, angle.sin() * 2.2)
                } else {
                    (
                        side * speed * if b.kind == Kind::Pound { 1.6 } else { 1.0 },
                        -0.5 - ((seed >> 8) % 10) as f64 / 14.0,
                    )
                };
                // 4 px puffs shrinking to 2 px (level pixels, scaled with the camera).
                let size = (4.0 - 2.0 * age as f64 / LIFE as f64).round();
                let mut color = PALETTE[(seed as usize) % PALETTE.len()];
                color[3] = 1.0 - age as f32 / LIFE as f32;
                out.push(Particle {
                    rect: [
                        (b.at[0] + vx * t - size / 2.0).round(),
                        (b.at[1] + vy * t + 0.03 * t * t - size).round(),
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
/// Intersect the player's vertical line with the compiled water polygons. Reject
/// internal tile/layer edges using the same public polygon query as the core.
/// This runs only on a swimming edge, not per frame or per simulation step.
fn water_surface(map: &Map, x: f64, near_y: f64) -> Option<f64> {
    let sx = (x * SCALE as f64).round() as i64;
    let wet = |y| {
        map.layers
            .iter()
            .any(|l| l.water && l.overlaps_box([sx, y, sx, y]))
    };
    let mut nearest: Option<f64> = None;
    for layer in map.layers.iter().filter(|l| l.water) {
        let size = layer.tile_size_pixels * SCALE;
        let col = sx.div_euclid(size);
        if col < 0 || col >= layer.width as i64 {
            continue;
        }
        let local_x = (sx - col * size) as f64;
        for row in 0..layer.height {
            let cell = layer.cells[row * layer.width + col as usize];
            let Some(contact) = layer.collision.iter().find(|c| c.cell == cell) else {
                continue;
            };
            for (a, b) in contact
                .polygon
                .iter()
                .zip(contact.polygon.iter().cycle().skip(1))
            {
                if a.x == b.x || local_x < a.x.min(b.x) as f64 || local_x > a.x.max(b.x) as f64 {
                    continue;
                }
                let y = row as f64 * size as f64
                    + a.y as f64
                    + (local_x - a.x as f64) * (b.y - a.y) as f64 / (b.x - a.x) as f64;
                let sy = y.round() as i64;
                if !wet(sy - 1) && wet(sy + 1) {
                    let py = y / SCALE as f64;
                    if nearest.is_none_or(|old| (py - near_y).abs() < (old - near_y).abs()) {
                        nearest = Some(py);
                    }
                }
            }
        }
    }
    nearest
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
            pickup_serial: 0,
            pickup: None,
            swimming: false,
            vy: 0.0,
            surface: None,
        }
    }
    #[test]
    fn swimming_edges_splash_at_surface_and_fast_entry_is_bigger() {
        let s = FeelSettings {
            dust_enabled: false,
            ..FeelSettings::default()
        };
        let entry = |speed: f64| {
            let mut d = Dust::default();
            let mut a = sample(10, false, 0, false);
            a.vy = speed;
            d.observe_sample(a, s);
            let mut b = sample(11, false, 0, false);
            b.swimming = true;
            b.surface = Some(60.0);
            d.observe_sample(b, s);
            d.observe_sample(b, s);
            (d, b)
        };
        let (mut slow, _) = entry(1.0);
        let (mut fast, mut b) = entry(10.0);
        let first = fast.particles(11, 1, s);
        assert_eq!(first.len(), 12);
        assert!(first.len() > slow.particles(11, 1, s).len());
        assert!(first.iter().all(|p| p.rect[1] + p.rect[3] == 60.0));
        let up = fast.particles(15, 1, s);
        assert!(up.iter().all(|p| p.rect[1] < 60.0));
        assert!(fast.particles(35, 1, s).is_empty());
        b.tick = 36;
        b.swimming = false;
        fast.observe_sample(b, s);
        assert!(!fast.particles(36, 1, s).is_empty());
        assert!(
            fast.particles(
                36,
                1,
                FeelSettings {
                    splash_enabled: false,
                    ..s
                }
            )
            .is_empty()
        );
        b.tick = 5;
        fast.observe_sample(b, s);
        assert!(fast.particles(5, 1, s).is_empty());
    }
    #[test]
    fn surface_query_uses_compiled_lagoon_water_and_not_internal_tile_edges() {
        let mut level: serde_json::Value =
            serde_json::from_str(include_str!("../../../../tests/fixtures/lagoon.level.json"))
                .unwrap();
        let water = &mut level["maps"]["map1"]["layer1"]["water3"];
        // Full water tiles make a continuous pool; its internal row edges are not surfaces.
        *water = water.as_str().unwrap().replace("24x0", "24x1").into();
        let world = eggshell_spike_core::World::compile(
            &level.to_string(),
            include_str!("../../../../src/level/collision_table.json"),
        )
        .unwrap();
        let map = &world.maps[0];
        assert_eq!(water_surface(map, 1100.0, 356.0), Some(320.0));
        assert_eq!(water_surface(map, 1100.0, 420.0), Some(320.0));
        assert_eq!(water_surface(map, 1000.0, 356.0), None);
    }
    #[test]
    fn explicit_pickup_signal_sparkles_once_at_pickup_even_without_dust() {
        let s = FeelSettings {
            dust_enabled: false,
            dust_amount: 0,
            ..FeelSettings::default()
        };
        let mut d = Dust::default();
        let mut before = sample(10, false, 0, false);
        before.pickup_serial = 4;
        before.pickup = Some([20.0, 30.0]);
        d.observe_sample(before, s); // Initial/restored signal is not replayed.
        assert!(d.particles(10, 1, s).is_empty());
        let mut collected = before;
        collected.tick = 11;
        collected.pickup_serial = 5;
        d.observe_sample(collected, s);
        let first = d.particles(11, 1, s);
        assert!((4..=6).contains(&first.len()));
        assert!(
            first
                .iter()
                .all(|p| (p.rect[0] - 20.0).abs() < 9.0 && (p.rect[1] - 30.0).abs() < 9.0)
        );
        d.observe_sample(collected, s);
        assert_eq!(first, d.particles(11, 1, s));
        collected.tick = 12;
        d.observe_sample(collected, s); // Persistent serial is not another event.
        assert_eq!(first.len(), d.particles(12, 1, s).len());
        assert!(
            d.particles(
                12,
                1,
                FeelSettings {
                    sparkle_enabled: false,
                    ..s
                }
            )
            .is_empty()
        );
        assert!(d.particles(27, 1, s).is_empty());
        collected.tick = 28;
        collected.pickup_serial = 6;
        collected.pickup = None; // A different sound must not create sparkles.
        d.observe_sample(collected, s);
        assert!(d.particles(28, 1, s).is_empty());
        d.observe_sample(before, s);
        assert!(d.particles(10, 1, s).is_empty());
    }
    #[test]
    fn pickup_between_draws_has_the_same_deterministic_twinkle() {
        let s = FeelSettings::default();
        let mut skipped = Dust::default();
        let mut every = Dust::default();
        for tick in 10..=14 {
            let mut next = sample(tick, false, 0, false);
            next.pickup_serial = i64::from(tick >= 11);
            next.pickup = Some([40.0, 50.0]);
            skipped.observe_sample(next, s);
            every.observe_sample(next, s);
            every.particles(tick, 1, s);
        }
        assert_eq!(skipped.particles(14, 1, s), every.particles(14, 1, s));
        assert!(!skipped.particles(14, 1, s).is_empty());
    }
    #[test]
    fn landing_pound_hit_decay_repeat_and_restore() {
        let s = FeelSettings::default();
        let mut d = Dust::default();
        d.observe_sample(sample(10, false, 0, false), s);
        d.observe_sample(sample(11, true, 0, false), s);
        let first = d.particles(11, 1, s);
        assert_eq!(first.len(), 8);
        d.observe_sample(sample(11, true, 0, false), s);
        assert_eq!(first, d.particles(11, 1, s));
        let later = d.particles(20, 1, s);
        assert_eq!(later.len(), 8);
        assert!(later[0].color[3] < first[0].color[3]);
        assert!(d.particles(39, 1, s).is_empty());
        d.observe_sample(sample(40, false, 2, false), s);
        d.observe_sample(sample(41, true, 3, false), s);
        assert_eq!(d.particles(41, 1, s).len(), 16);
        d.observe_sample(sample(42, true, 0, true), s);
        assert_eq!(d.particles(42, 1, s).len(), 28);
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
        assert_eq!(d.particles(13, 1, s).len(), 20);
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
        assert_eq!(d.particles(13, 1, s).len(), 16); // POUND_LAND not observed.
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
