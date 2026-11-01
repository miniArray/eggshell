//! Spike (#17 part 2): a short camera shake on ground-pound landings and hits.
//! Drawing only. It reads the presentation and its saved tick, never the session,
//! so it pauses with the simulation and a replay shakes the same way.
//! `EGGSHELL_SHAKE=off` turns it off.
use crate::feel::FeelSettings;
use eggshell_spike_core::{Lifetime, Presentation};

/// moves.gd POUND_FALL and POUND_LAND.
const POUND_FALL: i64 = 2;
const POUND_LAND: i64 = 3;

#[derive(Debug)]
pub struct Shake {
    pub enabled: bool,
    pub settings: FeelSettings,
    start: Option<i64>,
    kind: (f64, i64),
    last_tick: Option<i64>,
    last_action: i64,
    last_hurt: bool,
}

impl Default for Shake {
    fn default() -> Self {
        Self {
            enabled: std::env::var("EGGSHELL_SHAKE").map_or(true, |v| v != "off"),
            settings: FeelSettings::default(),
            start: None,
            kind: (0.0, 6),
            last_tick: None,
            last_action: 0,
            last_hurt: false,
        }
    }
}

impl Shake {
    /// Watch for the first step of a pound landing or a hit. Same-tick calls are ignored.
    pub fn observe(&mut self, p: &Presentation) {
        self.observe_parts(p.tick, p.player.action, p.player.lifetime == Lifetime::Hurt);
    }

    fn observe_parts(&mut self, tick: i64, action: i64, hurt: bool) {
        match self.last_tick {
            Some(last) if tick < last => self.start = None, // restore or restart
            Some(last) if tick > last => {
                // POUND_LAND can last a single step, and a slow or dumped frame may never
                // draw it. Leaving POUND_FALL for anything else also means the pound landed.
                let landed = (action == POUND_LAND && self.last_action != POUND_LAND)
                    || (self.last_action == POUND_FALL && action != POUND_FALL);
                if landed {
                    self.begin(
                        tick,
                        (
                            self.settings.pound_strength_px as f64,
                            self.settings.pound_steps,
                        ),
                    );
                } else if hurt && !self.last_hurt {
                    self.begin(
                        tick,
                        (
                            self.settings.hit_strength_px as f64,
                            self.settings.hit_steps,
                        ),
                    );
                }
            }
            _ => {}
        }
        self.last_tick = Some(tick);
        self.last_action = action;
        self.last_hurt = hurt;
    }

    /// The camera offset in level pixels at `tick`; zero when no shake runs.
    pub fn offset(&self, tick: i64) -> [f64; 2] {
        let Some(start) = self
            .start
            .filter(|_| self.enabled && self.settings.shake_enabled)
        else {
            return [0.0, 0.0];
        };
        let elapsed = tick - start;
        if elapsed < 0 || elapsed >= self.kind.1 {
            return [0.0, 0.0];
        }
        let fade = 1.0 - elapsed as f64 / self.kind.1 as f64;
        let strength = self.kind.0 * fade * fade;
        let angle =
            (hash((start * 977 + elapsed) as u64) % 360) as f64 * std::f64::consts::PI / 180.0;
        // A landing reads as vertical; x moves at half strength.
        [angle.cos() * 0.5 * strength, angle.sin() * strength]
    }

    fn begin(&mut self, tick: i64, kind: (f64, i64)) {
        // A stronger shake already running is not cut short.
        if self
            .start
            .is_some_and(|start| tick - start < self.kind.1 && self.kind.0 > kind.0)
        {
            return;
        }
        self.start = Some(tick);
        self.kind = kind;
    }
}

fn hash(value: u64) -> u64 {
    let mut x = value.wrapping_mul(0x9E37_79B9_7F4A_7C15);
    x ^= x >> 31;
    x = x.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x ^ (x >> 29)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn step(shake: &mut Shake, tick: i64, action: i64, hurt: bool) -> [f64; 2] {
        shake.observe_parts(tick, action, hurt);
        shake.offset(tick)
    }

    fn len(v: [f64; 2]) -> f64 {
        (v[0] * v[0] + v[1] * v[1]).sqrt()
    }

    #[test]
    fn pound_landing_shakes_then_stops() {
        let mut s = Shake {
            enabled: true,
            ..Shake::default()
        };
        assert_eq!(step(&mut s, 10, 2, false), [0.0, 0.0]);
        let first = step(&mut s, 11, POUND_LAND, false);
        assert!(len(first) > 0.0 && len(first) <= 3.0);
        assert_eq!(s.offset(11 + s.settings.pound_steps), [0.0, 0.0]);
    }

    #[test]
    fn pound_landing_between_drawn_frames_still_shakes() {
        let mut s = Shake {
            enabled: true,
            ..Shake::default()
        };
        step(&mut s, 10, POUND_FALL, false);
        // The one POUND_LAND step (11) was never drawn; 13 is back to normal.
        assert!(len(step(&mut s, 13, 0, false)) > 0.0);
    }

    #[test]
    fn hit_shakes_and_restore_clears() {
        let mut s = Shake {
            enabled: true,
            ..Shake::default()
        };
        step(&mut s, 20, 0, false);
        assert!(len(step(&mut s, 21, 0, true)) > 0.0);
        assert_eq!(step(&mut s, 5, 0, false), [0.0, 0.0]);
    }

    #[test]
    fn disabled_stays_still() {
        let mut s = Shake {
            enabled: false,
            ..Shake::default()
        };
        step(&mut s, 10, 2, false);
        assert_eq!(step(&mut s, 11, POUND_LAND, false), [0.0, 0.0]);
    }
}
