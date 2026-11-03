//! count_ledge.gd (o32): a numbered top-only ledge. Each time something steps on and off
//! it, its number drops by one; stepping off at one breaks it.
use crate::{entity::Kind, state::Run, Error, Placement, SCALE as S};
const MAX_COUNT: i64 = 99;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Ledge {
    pub count: i64,
    pub pressed: i64,
}

/// count_ledge.gd _overlap: strict on every side.
fn overlap(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Ledge {
    /// count_ledge.gd prepare + create. A form of 99 or more degrades the object to a
    /// placeholder in Godot; it is refused here.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        if !(0..MAX_COUNT).contains(&p.variant) {
            return Err(Error::Unsupported {
                requirements: vec![format!("countdown ledge form F={}", p.variant)],
            });
        }
        Ok(Self {
            count: p.variant + 1,
            pressed: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-32 * S, -26 * S, 32 * S, 32 * S]
    }
    /// count_ledge.gd solid_box: a 2 px top edge.
    pub fn solid(&self, e: &crate::entity::Entity) -> Option<[i64; 4]> {
        let top = e.body.y - 26 * S;
        (e.status == 1).then_some([e.body.x - 32 * S, top, e.body.x + 32 * S, top + 2 * S])
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "count" => self.count,
            "pressed" => self.pressed,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "count" => self.count = value,
            "pressed" => self.pressed = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (0..=MAX_COUNT).contains(&self.count) && [0, 1].contains(&self.pressed)
    }
}

impl Run {
    /// count_ledge.gd _bodies: enemies, o4 stars, o7 eggs and o17 producers (pads have no
    /// bounds) that are not held, hidden or collected; whether any one's world box, top
    /// and vertical speed meet `test`. Only rows of a pressing kind are visited (kinds
    /// never change in place; rows appended since the list was made are visited too),
    /// and bodies more than 2048 px away, which no type's bounds reach from there, are
    /// skipped before their bounds are read (Near.nearby is a region query too).
    fn ledge_any(&mut self, index: usize, test: impl Fn([i64; 4], i64, i64) -> bool) -> bool {
        const REACH: i64 = 2048 * S;
        let presses = |e: &crate::entity::Entity| {
            matches!(
                e.kind,
                Kind::Walker(_) | Kind::Star(_) | Kind::Egg(_) | Kind::Stem(_) | Kind::Hound(_)
            )
        };
        // Rebuilt after compaction (compact resets it) or a restore (a fresh Run).
        if self.presser_rows.0 > self.entities.len() {
            self.presser_rows = (
                self.entities.len(),
                (0..self.entities.len())
                    .filter(|&i| presses(&self.entities[i]))
                    .collect(),
            );
        }
        let at = self.entities[index].body;
        let tail = self.presser_rows.0..self.entities.len();
        self.presser_rows.1.iter().copied().chain(tail).any(|i| {
            let o = &self.entities[i];
            if i == index
                || o.status != 1
                || o.collected != 0
                || (o.body.x - at.x).abs() > REACH
                || (o.body.y - at.y).abs() > REACH
                || !match &o.kind {
                    // count_ledge.gd _bodies: registry enemies only (e33 is not one).
                    Kind::Walker(w) => w.held == 0 && w.hidden == 0 && o.is_enemy(),
                    Kind::Star(p) => p.held == 0,
                    Kind::Egg(_) | Kind::Stem(_) | Kind::Hound(_) => true,
                    _ => false,
                }
            {
                return false;
            }
            let b = crate::egg::entity_bounds(o);
            test(
                [
                    o.body.x + b[0],
                    o.body.y + b[1],
                    o.body.x + b[2],
                    o.body.y + b[3],
                ],
                o.body.y,
                o.body.vy,
            )
        })
    }
    fn ledge_player_box(&self) -> Option<[i64; 4]> {
        (self.player.captured_by == 0).then(|| {
            let b = self.player.bounds();
            let p = self.player.body;
            [p.x + b[0], p.y + b[1], p.x + b[2], p.y + b[3]]
        })
    }
    /// count_ledge.gd contact.
    pub(crate) fn ledge_contact(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Ledge(l) = &e.kind else {
            return;
        };
        if e.status != 1 {
            return;
        }
        let (x, y, pressed) = (e.body.x, e.body.y, l.pressed != 0);
        let top = y - 26 * S;
        let lowered = |b: [i64; 4]| [b[0], b[1] + 2 * S, b[2], b[3] + 2 * S];
        if !pressed {
            // Something whose box, 2 px lower, touches the ledge, with its origin at or
            // above the top and not moving up.
            let area = [x - 32 * S, y - 26 * S, x + 32 * S, y + 32 * S];
            let player = self.ledge_player_box().is_some_and(|b| {
                self.player.body.y <= top && self.player.body.vy >= 0 && overlap(lowered(b), area)
            });
            let pressing = player
                || self.ledge_any(index, |b, by, vy| {
                    by <= top && vy >= 0 && overlap(lowered(b), area)
                });
            if pressing {
                if let Kind::Ledge(l) = &mut self.entities[index].kind {
                    l.pressed = 1;
                }
            }
            return;
        }
        // The ledge raised by 2 px still touches something.
        let raised = [x - 32 * S, y - 28 * S, x + 32 * S, y + 30 * S];
        if self.ledge_player_box().is_some_and(|b| overlap(b, raised))
            || self.ledge_any(index, |b, _, _| overlap(b, raised))
        {
            return;
        }
        let e = &mut self.entities[index];
        if let Kind::Ledge(l) = &mut e.kind {
            l.pressed = 0;
            l.count -= 1;
            if l.count < 1 {
                e.status = 3;
            }
        }
    }
}
