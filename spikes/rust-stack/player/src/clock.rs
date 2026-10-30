//! No owed tick is discarded. Pausing explicitly excludes wall time.
use std::time::{Duration, Instant};
pub const HZ: u128 = 60;
#[derive(Debug)]
pub struct FrameClock {
    last: Instant,
    debt_ns60: u128,
    pub completed: u64,
    pub max_debt: u64,
}
impl FrameClock {
    pub fn new(now: Instant) -> Self {
        Self {
            last: now,
            debt_ns60: 0,
            completed: 0,
            max_debt: 0,
        }
    }
    pub fn observe(&mut self, now: Instant, paused: bool) {
        let elapsed = now.duration_since(self.last);
        self.last = now;
        if !paused {
            self.add_elapsed(elapsed);
        }
    }
    pub fn add_elapsed(&mut self, elapsed: Duration) {
        self.debt_ns60 += elapsed.as_nanos() * HZ;
        self.max_debt = self.max_debt.max(self.owed());
    }
    pub fn owed(&self) -> u64 {
        (self.debt_ns60 / 1_000_000_000) as u64
    }
    /// Call only after an authoritative advance succeeds.
    pub fn completed_one(&mut self) {
        assert!(self.owed() > 0);
        self.debt_ns60 -= 1_000_000_000;
        self.completed += 1;
    }
    pub fn fraction(&self) -> f64 {
        (self.debt_ns60 % 1_000_000_000) as f64 / 1_000_000_000.0
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ten_minutes_no_drift() {
        let mut clock = FrameClock::new(Instant::now());
        for _ in 0..600_000 {
            clock.add_elapsed(Duration::from_millis(1));
            while clock.owed() > 0 {
                clock.completed_one();
            }
        }
        assert_eq!(clock.completed, 36_000);
        assert_eq!(clock.owed(), 0);
        assert_eq!(clock.fraction(), 0.0);
    }
    #[test]
    fn slow_draw_never_discards_steps() {
        let mut c = FrameClock::new(Instant::now());
        c.add_elapsed(Duration::from_millis(250));
        assert_eq!(c.owed(), 15);
        c.completed_one();
        assert_eq!(c.owed(), 14);
    }
}
