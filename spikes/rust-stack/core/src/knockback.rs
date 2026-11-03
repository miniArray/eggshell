//! knockback.gd: persisted ordered value-tween rows.
use crate::Error;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Tween {
    pub from_vx: i64,
    pub remaining: i64,
    pub total: i64,
    pub phase: i64,
}
impl Tween {
    pub fn valid(&self) -> bool {
        (-1024 * 60..=1024 * 60).contains(&self.from_vx)
            && (1..=600).contains(&self.total)
            && (0..=self.total).contains(&self.remaining)
            && (0..=3).contains(&self.phase)
            && (self.phase != 0 || self.remaining == self.total)
            && (self.phase != 3 || self.remaining == 0)
    }
    pub fn row(&self) -> Vec<i64> {
        vec![self.from_vx, self.remaining, self.total, self.phase]
    }
    pub fn from_row(row: &[i64]) -> Result<Self, Error> {
        let [from_vx, remaining, total, phase] = row else {
            return Err(refuse());
        };
        let tween = Self {
            from_vx: *from_vx,
            remaining: *remaining,
            total: *total,
            phase: *phase,
        };
        if !tween.valid() {
            return Err(refuse());
        }
        Ok(tween)
    }
}
fn refuse() -> Error {
    Error::Unsupported {
        requirements: vec!["snapshot knock_tweens row outside knockback.gd bounds".into()],
    }
}
