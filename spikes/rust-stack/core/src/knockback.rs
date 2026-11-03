//! knockback.gd: the ordered knockBackTimer value tweens owned by armor (e11) and small
//! soft walkers (e23). Eligibility (knock_active) is independent of the lifetimes of
//! these value tweens.
use crate::{
    actors::{Actor, ActorKind},
    entity::Kind,
    state::Run,
    Error,
};
pub(crate) const SCHEDULED: i64 = 0;
pub(crate) const PLAYING: i64 = 1;
pub(crate) const WAITING_RELEASE: i64 = 2;
pub(crate) const FINISHED_WAITING: i64 = 3;

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
    fn waiting(&self) -> bool {
        [WAITING_RELEASE, FINISHED_WAITING].contains(&self.phase)
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

impl Actor {
    /// knockback.gd start: value tweens permit repeated tags; a start never stops an
    /// existing one.
    pub(crate) fn knock_start(&mut self, from_vx: i64, ticks: i64) {
        self.knock_tweens.push(Tween {
            from_vx,
            remaining: ticks,
            total: ticks,
            phase: SCHEDULED,
        });
        self.knock_active = 1;
    }
    /// knockback.gd stop: every running tween waits for release, after the ones already
    /// waiting (release order need not be registration order). Eligibility is unchanged.
    pub(crate) fn knock_stop(&mut self) {
        let (mut waiting, mut stopped): (Vec<Tween>, Vec<Tween>) =
            self.knock_tweens.drain(..).partition(Tween::waiting);
        for tween in &mut stopped {
            tween.phase = WAITING_RELEASE;
        }
        waiting.append(&mut stopped);
        self.knock_tweens = waiting;
    }
    /// knockback.gd clear
    pub(crate) fn knock_clear(&mut self) {
        self.knock_tweens.clear();
        self.knock_active = 0;
    }
    /// knockback.gd value: the first active row in registration order, else the first
    /// waiting row in release order.
    pub(crate) fn knock_value(&self) -> i64 {
        for waiting in [false, true] {
            if let Some(t) = self.knock_tweens.iter().find(|t| t.waiting() == waiting) {
                return t.from_vx * t.remaining / t.total;
            }
        }
        0
    }
    /// knockback.gd deferred: a new start must not replace this step's ordinary motion.
    pub(crate) fn knock_deferred(&self) -> bool {
        let mut scheduled = false;
        for tween in &self.knock_tweens {
            if tween.phase == PLAYING {
                return false;
            }
            scheduled |= tween.phase == SCHEDULED;
        }
        scheduled
    }
    /// knockback.gd pending: an active row has run out.
    pub(crate) fn knock_pending(&self) -> bool {
        self.knock_tweens
            .iter()
            .any(|t| !t.waiting() && t.remaining == 0)
    }
    /// knockback.gd finish (tick2): old waiting rows are released; a natural completion
    /// clears eligibility and waits until the next tick2.
    pub(crate) fn knock_finish(&mut self, status: i64) {
        if status != 1 {
            self.knock_clear();
            return;
        }
        if !self
            .knock_tweens
            .iter()
            .any(|t| t.waiting() || t.remaining == 0)
        {
            return;
        }
        let mut active = Vec::new();
        let mut completed = Vec::new();
        for mut tween in self.knock_tweens.drain(..) {
            if tween.waiting() {
                continue;
            }
            if tween.remaining == 0 {
                self.knock_active = 0;
                tween.phase = FINISHED_WAITING;
                completed.push(tween);
            } else {
                active.push(tween);
            }
        }
        active.append(&mut completed);
        self.knock_tweens = active;
    }
    /// armored_walker.gd / soft_walker.gd knockback_active.
    pub(crate) fn knockback_active(&self) -> bool {
        match self.kind {
            ActorKind::Armored => self.knock_active == 1,
            ActorKind::SoftWalker => self.mode == crate::soft::KNOCKED && self.knock_active == 1,
            _ => false,
        }
    }
}

impl Run {
    /// knockback.gd advance (armored_walker.gd before_advance): one pretick per step
    /// ticks every surviving row, even of an ineligible owner.
    pub(crate) fn knock_advance(&mut self) {
        for e in &mut self.entities {
            let Kind::Walker(w) = &mut e.kind else {
                continue;
            };
            if ![ActorKind::Armored, ActorKind::SoftWalker].contains(&w.kind) {
                continue;
            }
            if e.status != 1 {
                w.knock_clear();
                continue;
            }
            for tween in &mut w.knock_tweens {
                if !tween.waiting() {
                    tween.phase = PLAYING;
                    tween.remaining = (tween.remaining - 1).max(0);
                }
            }
        }
    }
    /// armored_walker.gd _first_knock_velocity: the value of the first-born eligible body
    /// of the family.
    pub(crate) fn first_knock_velocity(&self) -> i64 {
        let mut first: Option<&Actor> = None;
        for e in &self.entities {
            let Kind::Walker(w) = &e.kind else {
                continue;
            };
            if e.status != 1 || !w.knockback_active() {
                continue;
            }
            if first.is_none_or(|f| w.born_before(f)) {
                first = Some(w);
            }
        }
        first.map_or(0, Actor::knock_value)
    }
}

#[cfg(test)]
mod tween_tests {
    use super::*;
    use crate::Position;

    #[test]
    fn knockback_tweens_keep_registration_then_release_order() {
        let mut armor = Actor::new(ActorKind::Armored, 0, 0, Position::default());
        armor.knock_start(448 * 60, 60);
        assert!(armor.knock_deferred());
        assert_eq!(armor.knock_value(), 448 * 60);
        // A wall rebound stops the running row and starts a new one; the new one leads.
        armor.knock_tweens[0].phase = PLAYING;
        armor.knock_tweens[0].remaining = 30;
        armor.knock_stop();
        armor.knock_start(-48 * 60, 90);
        assert_eq!(armor.knock_value(), -48 * 60);
        assert_eq!(armor.knock_tweens[0].phase, WAITING_RELEASE);
        // tick2 releases the waiting row; a finished row clears eligibility and waits.
        armor.knock_tweens[1].phase = PLAYING;
        armor.knock_tweens[1].remaining = 0;
        assert!(armor.knock_pending());
        armor.knock_finish(1);
        assert_eq!(armor.knock_active, 0);
        assert_eq!(armor.knock_tweens.len(), 1);
        assert_eq!(armor.knock_tweens[0].phase, FINISHED_WAITING);
        assert_eq!(armor.knock_value(), 0);
        armor.knock_finish(1);
        assert!(armor.knock_tweens.is_empty());
    }
}
