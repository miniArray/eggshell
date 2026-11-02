//! Drawing-only emitters. Saved ticks drive flicker; no RNG or simulation writes.
use crate::screen::Plan;
use eggshell_spike_core::{EntityPicture, SCALE};

pub const MAX_LIGHTS: usize = 16;
/// Warm fire, gold and lava accents, not a replacement for the map visibility mask.
const FIRE: [f32; 3] = [1.0, 0.48, 0.16];
const GOLD: [f32; 3] = [1.0, 0.78, 0.28];
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Light {
    pub at: [f32; 2],
    pub radius: f32,
    pub color: [f32; 3],
    pub intensity: f32,
    pub glow: f32,
}
#[derive(Clone, Debug)]
pub struct Frame {
    pub lights: Vec<Light>,
    pub candidates: usize,
    pub dark_map: bool,
    pub auto_normals: bool,
    pub style: crate::feel::GlowStyle,
    /// Screen offset and level-pixel scale, including camera shake.
    pub grid: [f32; 3],
    center: [f32; 2],
}
impl Frame {
    pub fn new(container: [f64; 2], darkness: f64) -> Self {
        Self {
            lights: Vec::with_capacity(MAX_LIGHTS),
            candidates: 0,
            dark_map: darkness > 0.0,
            auto_normals: false,
            style: crate::feel::GlowStyle::Pixel,
            grid: [0.0, 0.0, 1.0],
            center: container.map(|v| v as f32 / 2.0),
        }
    }
    #[allow(clippy::too_many_arguments)]
    pub fn add(
        &mut self,
        at: [f64; 2],
        radius: f64,
        color: [f32; 3],
        intensity: f32,
        glow: f32,
        tick: i64,
        plan: &Plan,
    ) {
        self.grid = [
            crate::screen::godot_round(plan.offset[0]) as f32,
            crate::screen::godot_round(plan.offset[1]) as f32,
            plan.scale as f32,
        ];
        let phase = at[0] as f32 * 0.071 + at[1] as f32 * 0.037;
        let at = [
            at[0] * plan.scale + plan.offset[0],
            at[1] * plan.scale + plan.offset[1],
        ]
        .map(|v| v as f32);
        let radius = (radius * plan.scale) as f32;
        if (0..2).any(|i| at[i] + radius < 0.0 || at[i] - radius > self.center[i] * 2.0) {
            return;
        }
        self.candidates += 1;
        // Spatial phase avoids lamps pulsing together. A restored tick gives the same frame.
        let flicker = 0.96 + 0.04 * (tick as f32 * 0.17 + phase).sin();
        self.lights.push(Light {
            at,
            radius,
            color,
            intensity: intensity * flicker,
            glow: glow * flicker,
        });
        let center = self.center;
        self.lights
            .sort_by(|a, b| distance2(a.at, center).total_cmp(&distance2(b.at, center)));
        self.lights.truncate(MAX_LIGHTS);
    }
    pub fn entity(&mut self, e: &EntityPicture, tick: i64, plan: &Plan) {
        if !e.visible || e.hidden || e.held {
            return;
        }
        let Some((radius, color, intensity)) = source(
            &e.code,
            e.visual.animation.as_deref(),
            e.variant,
            e.visual.alpha,
        ) else {
            return;
        };
        let b = e.body_bounds.map(|v| v as f64 / SCALE as f64);
        let at = [
            e.motion.current.x as f64 / SCALE as f64 + (b[0] + b[2]) / 2.0,
            e.motion.current.y as f64 / SCALE as f64 + (b[1] + b[3]) / 2.0,
        ];
        let glow = match e.code.as_str() {
            "o1" | "o2" => 0.4,
            "o5" => 0.7,
            _ => 1.0,
        };
        self.add(at, radius, color, intensity, glow, tick, plan);
    }
    pub fn lava(&mut self, at: [f64; 2], tick: i64, plan: &Plan) {
        self.add(at, 72.0, FIRE, 0.65, 0.0, tick, plan);
    }
    pub fn apply_settings(&mut self, s: crate::feel::FeelSettings) {
        self.auto_normals = s.auto_normals;
        self.style = s.glow_style;
        let light = if s.lights_enabled {
            s.light_strength.clamp(0, 3) as f32 / 2.0
        } else {
            0.0
        };
        let glow = if s.glow_enabled {
            s.glow_strength.clamp(0, 3) as f32
        } else {
            0.0
        };
        for l in &mut self.lights {
            l.intensity *= light;
            l.glow *= glow;
        }
    }
    pub fn budget(&mut self) {
        // Bound total additive energy, including dense coin/lava clusters.
        let sum: f32 = self.lights.iter().map(|l| l.intensity).sum();
        if sum > 3.0 {
            for l in &mut self.lights {
                l.intensity *= 3.0 / sum;
            }
        }
        let sum: f32 = self.lights.iter().map(|l| l.glow).sum();
        if sum > 3.0 {
            for l in &mut self.lights {
                l.glow *= 3.0 / sum;
            }
        }
    }
}
fn source(
    code: &str,
    animation: Option<&str>,
    variant: i64,
    alpha: f64,
) -> Option<(f64, [f32; 3], f32)> {
    Some(match code {
        "d25" | "d26" if animation.is_some_and(|a| a.starts_with("lit:")) => (100.0, FIRE, 1.0),
        "fire_shot" => (80.0, FIRE, 0.9),
        // e16 form 3 is cold; frozen bubbles are explicitly faded by Presentation.
        "e16" if variant != 3 && alpha >= 1.0 => (80.0, FIRE, 0.9),
        "o1" | "o2" => (36.0, GOLD, 0.18),
        "o5" => (72.0, GOLD, 0.0),
        _ => return None,
    })
}
fn distance2(a: [f32; 2], b: [f32; 2]) -> f32 {
    (a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2)
}

/// GLES dark-map blend is DST_COLOR, ONE_MINUS_SRC_ALPHA. Since each source
/// channel is <= alpha, it can only tint/darken, never uncover hidden geometry.
#[cfg(test)]
fn dark_tint(dst: f32, channel: f32, alpha: f32) -> f32 {
    dst * (channel * alpha + 1.0 - alpha)
}
#[cfg(test)]
mod tests {
    use super::*;
    // Reference evaluator for the shader's four-band brightness contract.
    fn pixel_band(brightness: f32, x: usize, y: usize) -> f32 {
        const BAYER: [[f32; 4]; 4] = [
            [0.0, 8.0, 2.0, 10.0],
            [12.0, 4.0, 14.0, 6.0],
            [3.0, 11.0, 1.0, 9.0],
            [15.0, 7.0, 13.0, 5.0],
        ];
        let edge = ((BAYER[y % 4][x % 4] + 0.5) / 16.0 - 0.5) * 0.12;
        ((brightness * 4.0 + 0.5 + edge).floor() / 4.0).clamp(0.0, 1.0)
    }
    #[test]
    fn pixel_bands_are_discrete_and_dither_only_near_edges() {
        for y in 0..4 {
            for x in 0..4 {
                for v in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    assert_eq!(pixel_band(v, x, y), v);
                }
                for n in 0..1000 {
                    let band = pixel_band(n as f32 / 999.0, x, y);
                    assert!([0.0, 0.25, 0.5, 0.75, 1.0].contains(&band));
                }
            }
        }
        let edge: Vec<_> = (0..4)
            .flat_map(|y| (0..4).map(move |x| pixel_band(0.375, x, y)))
            .collect();
        assert_eq!(edge.iter().filter(|v| **v == 0.25).count(), 8);
        assert_eq!(edge.iter().filter(|v| **v == 0.5).count(), 8);
        for v in [0.35, 0.4] {
            assert!((0..4).all(|y| (0..4).all(|x| pixel_band(v, x, y) == pixel_band(v, 0, 0))));
        }
    }
    #[test]
    fn screenshot_fixture_has_lamps_coins_goal_and_real_lava_layers() {
        let world = eggshell_spike_core::World::compile(
            include_str!("../tests/fixtures/lighting.level.json"),
            include_str!("../../../../src/level/collision_table.json"),
        )
        .unwrap();
        assert_eq!(world.maps.len(), 2);
        for map in &world.maps {
            for code in ["d25", "d26", "e16", "o1", "o2", "o5"] {
                assert!(map.placements.iter().any(|p| p.code == code));
            }
            let lava = map
                .layers
                .iter()
                .find(|l| l.hazard == eggshell_spike_core::TerrainHazard::Lava)
                .unwrap();
            assert_eq!(lava.cells.iter().filter(|c| **c != -1).count(), 4);
        }
        assert_eq!(world.maps[0].darkness_percent, 0);
        assert_eq!(world.maps[1].darkness_percent, 80);
    }
    #[test]
    fn dark_map_lights_never_increase_visible_area() {
        let world = eggshell_spike_core::World::compile(
            include_str!("../tests/fixtures/lighting.level.json"),
            include_str!("../../../../src/level/collision_table.json"),
        )
        .unwrap();
        let frame = Frame::new(
            [640.0, 480.0],
            world.maps[1].darkness_percent as f64 / 100.0,
        );
        assert!(frame.dark_map);
        for darkness in [0.01_f32, 0.5, 1.0] {
            let mut off = 0;
            let mut on = 0;
            for y in 0..480 {
                for x in 0..640 {
                    let d = (((x as f32 - 320.0).powi(2) + (y as f32 - 240.0).powi(2)).sqrt()
                        / 128.0)
                        .clamp(0.0, 1.0);
                    let baseline = 0.7 * (1.0 - darkness * d * d * (3.0 - 2.0 * d));
                    let mut lit = baseline;
                    for n in 0..MAX_LIGHTS {
                        lit = dark_tint(
                            lit,
                            FIRE[n % 3],
                            pixel_band(n as f32 / MAX_LIGHTS as f32, x, y),
                        );
                    }
                    assert!(lit <= baseline + 1e-6);
                    off += usize::from(baseline > 0.01);
                    on += usize::from(lit > 0.01);
                }
            }
            assert!(on <= off);
        }
    }
    #[test]
    fn sources_exclude_dim_cold_and_frozen() {
        assert!(source("d25", Some("dim:0:0"), 0, 1.0).is_none());
        assert!(source("d26", Some("lit:1:0"), 0, 1.0).is_some());
        assert!(source("e16", None, 3, 1.0).is_none());
        assert!(source("e16", None, 0, 0.6).is_none());
        for code in ["fire_shot", "e16", "o1", "o2"] {
            assert!(source(code, None, 0, 1.0).is_some());
        }
    }
    #[test]
    fn disabled_zero_strength_and_default_settings() {
        let plan =
            crate::screen::plan([640.0, 480.0], [2048.0, 480.0], [320.0, 240.0], 1, 0).unwrap();
        let mut frame = Frame::new([640.0, 480.0], 0.0);
        frame.add([320.0, 240.0], 72.0, FIRE, 1.0, 1.0, 5, &plan);
        let base = frame.lights.clone();
        frame.apply_settings(Default::default());
        assert_eq!(frame.lights.len(), base.len());
        for (light, base) in frame.lights.iter().zip(&base) {
            assert_eq!(light.intensity, base.intensity);
            assert_eq!(light.glow, base.glow * 2.0);
        }
        let mut disabled = frame.clone();
        disabled.apply_settings(crate::feel::FeelSettings {
            lights_enabled: false,
            glow_enabled: false,
            auto_normals: true,
            ..Default::default()
        });
        assert!(
            disabled
                .lights
                .iter()
                .all(|l| l.intensity == 0.0 && l.glow == 0.0)
        );
        frame.apply_settings(crate::feel::FeelSettings {
            light_strength: 0,
            glow_strength: 0,
            ..Default::default()
        });
        assert_eq!(frame.lights, disabled.lights);
    }
    #[test]
    fn goal_is_glow_only_and_glow_energy_is_bounded() {
        assert_eq!(source("o5", None, 0, 1.0).unwrap().2, 0.0);
        let plan =
            crate::screen::plan([640.0, 480.0], [2048.0, 480.0], [320.0, 240.0], 1, 0).unwrap();
        let mut frame = Frame::new([640.0, 480.0], 0.0);
        for _ in 0..MAX_LIGHTS {
            frame.add([320.0, 240.0], 72.0, GOLD, 0.0, 1.0, 5, &plan);
        }
        frame.budget();
        assert!(frame.lights.iter().map(|l| l.glow).sum::<f32>() <= 3.00001);
        assert!(frame.lights.iter().all(|l| l.intensity == 0.0));
    }
    #[test]
    fn cap_nearest_energy_and_saved_tick_repeat() {
        let plan =
            crate::screen::plan([640.0, 480.0], [2048.0, 480.0], [320.0, 240.0], 1, 0).unwrap();
        let mut a = Frame::new([640.0, 480.0], 0.0);
        for x in 0..100 {
            a.lava([x as f64 * 6.0, 240.0], 99, &plan);
        }
        assert_eq!(a.candidates, 100);
        assert_eq!(a.lights.len(), MAX_LIGHTS);
        assert!(
            a.lights
                .windows(2)
                .all(|p| distance2(p[0].at, a.center) <= distance2(p[1].at, a.center))
        );
        let mut b = a.clone();
        a.budget();
        b.budget();
        assert_eq!(a.lights, b.lights);
        assert!(a.lights.iter().map(|l| l.intensity).sum::<f32>() <= 3.00001);
    }
}
