//! Goal proximity and the music-only lift. No simulation or wall-clock writes.
use crate::feel::FeelSettings;
use eggshell_spike_core::{Position, Presentation, SCALE, World};

#[derive(Default)]
pub struct Proximity {
    goals: Vec<Vec<Position>>,
    last: Option<(i64, usize)>,
    value: f32,
    logged: Option<f32>,
}
impl Proximity {
    pub fn new(world: &World) -> Self {
        Self {
            goals: world
                .maps
                .iter()
                .map(|m| {
                    m.placements
                        .iter()
                        .filter(|p| p.code == "o5")
                        .map(|p| p.position)
                        .collect()
                })
                .collect(),
            ..Self::default()
        }
    }
    pub fn reset(&mut self) {
        self.last = None;
    }
    pub fn observe(&mut self, p: &Presentation, settings: FeelSettings) -> f32 {
        let at = p.player.motion.current;
        let target = self
            .goals
            .get(p.map_index.saturating_sub(1))
            .into_iter()
            .flatten()
            .map(|goal| {
                let dx = (at.x as f64 - goal.x as f64) / SCALE as f64;
                let dy = (at.y as f64 - goal.y as f64) / SCALE as f64 - 28.0;
                distance_curve(dx.hypot(dy))
            })
            .fold(0.0, f32::max);
        self.value = match self.last {
            Some((tick, map)) if map == p.map_index && p.tick >= tick => {
                smooth(self.value, target, p.tick - tick)
            }
            // On load/restore, use this location, not history from the old timeline.
            _ => target,
        };
        self.last = Some((p.tick, p.map_index));
        if self
            .logged
            .is_none_or(|old| (self.value - old).abs() >= 0.1)
        {
            println!("RUST_AUDIO_GOAL proximity={:.3}", self.value);
            self.logged = Some(self.value);
        }
        if settings.goal_music_enabled && !matches!(p.player.life_phase, 2..=5 | 7..=8) {
            self.value * settings.goal_music_strength.clamp(0, 3) as f32 / 3.0
        } else {
            0.0
        }
    }
}
fn distance_curve(distance: f64) -> f32 {
    // One screen away begins the lift; touching the goal reaches the full lift.
    ((640.0 - distance) / (640.0 - 64.0)).clamp(0.0, 1.0) as f32
}
fn smooth(value: f32, target: f32, steps: i64) -> f32 {
    // 60 Hz saved ticks, one-second time constant. Equal ticks do not advance it.
    target + (value - target) * (-(steps.max(0) as f32) / 60.0).exp()
}
pub fn gain(amount: f32) -> f32 {
    // Linear in decibels, bounded by +3 dB at strength 3.
    10.0_f32.powf(3.0 * amount.clamp(0.0, 1.0) / 20.0)
}

/// A 20 ms dezipper follows the per-step proximity. Presence is a gentle high
/// shelf above 1.5 kHz, applied to the streaming music bus only.
#[derive(Default)]
pub struct Lift {
    amount: f32,
    target: f32,
    low: [f32; 2],
}
impl Lift {
    pub fn clear_history(&mut self) {
        self.low = [0.0; 2];
    }
    pub fn set(&mut self, amount: f32) {
        self.target = amount.clamp(0.0, 1.0);
    }
    pub fn process(&mut self, music: &mut [f32]) {
        let alpha = 1.0 - (-2.0 * std::f32::consts::PI * 1500.0 / 48_000.0).exp();
        let slew = 1.0 / (48_000.0 * 0.020);
        for frame in music.chunks_exact_mut(2) {
            self.amount += (self.target - self.amount).clamp(-slew, slew);
            let gain = gain(self.amount);
            for ch in 0..2 {
                self.low[ch] += alpha * (frame[ch] - self.low[ch]);
                frame[ch] =
                    gain * (frame[ch] + (frame[ch] - self.low[ch]) * 0.12 * self.amount);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn smoothing_uses_saved_steps_and_is_independent_of_draws() {
        let mut every = 0.0;
        for _ in 0..60 {
            every = smooth(every, 1.0, 1);
        }
        let skipped = smooth(0.0, 1.0, 60);
        assert!((every - skipped).abs() < 1e-5);
        assert!((skipped - (1.0 - (-1.0_f32).exp())).abs() < 1e-6);
        assert_eq!(smooth(every, 0.0, 0), every);
        assert!(smooth(every, 0.0, 60) < every);
    }
    #[test]
    fn distance_and_gain_are_bounded_monotonic_and_musical() {
        assert_eq!(distance_curve(640.0), 0.0);
        assert_eq!(distance_curve(2000.0), 0.0);
        assert_eq!(distance_curve(64.0), 1.0);
        assert_eq!(distance_curve(0.0), 1.0);
        assert_eq!(distance_curve(352.0), 0.5);
        assert_eq!(gain(-1.0), 1.0);
        assert!((20.0 * gain(1.0).log10() - 3.0).abs() < 1e-5);
        assert_eq!(gain(2.0), gain(1.0));
        for i in 0..100 {
            assert!(gain(i as f32 / 100.0) < gain((i + 1) as f32 / 100.0));
        }
    }
    #[test]
    fn fallback_adds_gentle_presence_without_stereo_crosstalk() {
        let amplitude = |hz: f32| {
            let mut lift = Lift::default();
            lift.set(1.0);
            let mut samples: Vec<f32> = (0..24_000)
                .flat_map(|i| {
                    [
                        (i as f32 * 2.0 * std::f32::consts::PI * hz / 48_000.0).sin() * 0.1,
                        0.0,
                    ]
                })
                .collect();
            lift.process(&mut samples);
            assert!(samples.iter().skip(1).step_by(2).all(|&x| x == 0.0));
            let rms = (samples[24_000..]
                .iter()
                .step_by(2)
                .map(|x| x * x)
                .sum::<f32>()
                / 12_000.0)
                .sqrt();
            rms / (0.1 / 2.0_f32.sqrt())
        };
        let low = amplitude(100.0);
        let high = amplitude(8000.0);
        assert!((low - gain(1.0)).abs() < 0.01);
        assert!(high > low * 1.08 && high < low * 1.13);
    }
    #[test]
    fn dry_is_exact_and_gain_ramps_in_and_out() {
        let mut lift = Lift::default();
        let mut dry = [0.2, -0.3];
        lift.process(&mut dry);
        assert_eq!(dry, [0.2, -0.3]);
        lift.set(1.0);
        let mut base = vec![0.2; 48_000];
        lift.process(&mut base);
        assert!(base[0] > 0.2 && base[0] < 0.201);
        assert!((base[base.len() - 1] - 0.2 * gain(1.0)).abs() < 1e-6);
        lift.set(0.0);
        let mut base = vec![0.2; 48_000];
        lift.process(&mut base);
        assert_eq!(lift.amount, 0.0);
        assert_eq!(base[base.len() - 1], 0.2);
    }
}
