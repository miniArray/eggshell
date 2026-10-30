//! Godot-compatible fixed-integer arithmetic used by admitted simulation rules.
use crate::{schema::invalid, Error, Position, SCALE};

pub fn floor_div(value: i64, divisor: i64) -> Result<i64, Error> {
    if divisor <= 0 {
        return Err(invalid("floor_div requires a positive divisor"));
    }
    Ok(value / divisor - i64::from(value < 0 && value % divisor != 0))
}
pub fn round_units(pixels: f64) -> Result<i64, Error> {
    round_integer(pixels * SCALE as f64)
}
pub fn round_integer(units: f64) -> Result<i64, Error> {
    // f64's rounded representation of i64::MAX is already outside int64.
    if !units.is_finite() || units < i64::MIN as f64 || units >= -(i64::MIN as f64) {
        return Err(invalid("position exceeds int64"));
    }
    Ok(units.round() as i64)
}
pub fn approach(value: i64, target: i64, amount: i64) -> i64 {
    if value < target {
        value.wrapping_add(amount).min(target)
    } else {
        value.wrapping_sub(amount).max(target)
    }
}
pub fn sine(phase: i64, period: i64, amplitude: i64) -> Result<i64, Error> {
    if period < 2 {
        return Err(invalid("sine period must be at least two"));
    }
    let half = period / 2;
    let tick = phase % period;
    let sign: i64 = if tick < half { 1 } else { -1 };
    let x = tick % half;
    let product = x.wrapping_mul(half.wrapping_sub(x));
    let denominator = 5i64
        .wrapping_mul(half)
        .wrapping_mul(half)
        .wrapping_sub(4i64.wrapping_mul(product));
    if denominator == 0 {
        return Err(invalid("sine denominator is zero"));
    }
    sign.wrapping_mul(amplitude)
        .wrapping_mul(16)
        .wrapping_mul(product)
        .checked_div(denominator)
        .ok_or_else(|| invalid("sine division overflow"))
}
pub fn root(value: i64) -> i64 {
    let mut low = 0;
    let mut high = value.min(1_000_000_000);
    while low < high {
        let middle = (low + high + 1) / 2;
        if middle <= value / middle {
            low = middle;
        } else {
            high = middle - 1;
        }
    }
    low
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rng(i64);
impl Rng {
    pub fn from_saved(value: i64) -> Result<Self, Error> {
        if !(0..=0x7fff_ffff).contains(&value) {
            return Err(invalid("RNG state"));
        }
        Ok(Self(value))
    }
    pub fn saved(self) -> i64 {
        self.0
    }
    /// One step of the shared LCG, returning the new state (moves.gd seed spread).
    pub fn lcg_step(&mut self) -> i64 {
        self.next()
    }
    fn next(&mut self) -> i64 {
        self.0 = self.0.wrapping_mul(1_103_515_245).wrapping_add(12_345) & 0x7fff_ffff;
        self.0
    }
    pub fn ticks(&mut self, low: i64, high: i64) -> i64 {
        low.wrapping_add(
            self.next()
                .wrapping_mul(high.wrapping_sub(low))
                .wrapping_add(2_147_483_647)
                / 2_147_483_648,
        )
    }
    pub fn cycles(&mut self) -> i64 {
        1 + (self.next() * 3 + 1_073_741_824) / 2_147_483_648
    }
}
/// Saved follow point only; activation never reads drawing viewport dimensions.
pub fn screen_centre(follow: Position, width: i64, height: i64) -> Position {
    let x = if follow.x > width - 416 * SCALE {
        width - 416 * SCALE
    } else if follow.x < 416 * SCALE {
        416 * SCALE
    } else {
        follow.x
    };
    let body_y = follow.y + 28 * SCALE;
    let y = if body_y > height - 160 * SCALE {
        height - 224 * SCALE
    } else if body_y < 288 * SCALE {
        224 * SCALE
    } else {
        body_y - 64 * SCALE
    };
    Position { x, y }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn integer_edges_and_rng_restore() {
        assert_eq!(floor_div(-1, 3600).unwrap(), -1);
        assert_eq!(floor_div(-3600, 3600).unwrap(), -1);
        assert_eq!(floor_div(3599, 3600).unwrap(), 0);
        assert!(floor_div(1, 0).is_err());
        assert_eq!(round_units(0.5 / 3600.0).unwrap(), 1);
        assert_eq!(round_units(-0.5 / 3600.0).unwrap(), -1);
        assert!(round_units(f64::INFINITY).is_err());
        let mut rng = Rng::from_saved(1).unwrap();
        for _ in 0..100 {
            rng.ticks(-192 * 60, 192 * 60);
        }
        let mut resumed = Rng::from_saved(rng.saved()).unwrap();
        assert_eq!(rng.cycles(), resumed.cycles());
        assert_eq!(rng.ticks(60, 150), resumed.ticks(60, 150));
    }
    #[test]
    fn reference_screen_small_map_right_and_bottom_limits_win() {
        let p = screen_centre(
            Position {
                x: 50 * SCALE,
                y: 50 * SCALE,
            },
            100 * SCALE,
            100 * SCALE,
        );
        assert_eq!(
            p,
            Position {
                x: -316 * SCALE,
                y: -124 * SCALE
            }
        );
    }
}
