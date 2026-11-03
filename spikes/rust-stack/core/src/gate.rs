//! one_way_gate.gd (o31): a full turned barrier that opens while a body occupies its
//! allowed entry side, and closes once no body is inside its area.
use crate::{
    entity::{Entity, Kind},
    state::Run,
    turn, Error, Placement, SCALE as S,
};
pub(crate) const BARRIER: [i64; 4] = [-64 * S, -16 * S, 64 * S, 16 * S];
const ENTRY: [i64; 4] = [-64 * S, 16 * S, 64 * S, 48 * S];
const AREA: [i64; 4] = [-64 * S, -16 * S, 64 * S, 48 * S];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Gate {
    pub angle: i64,
    pub opened: i64,
}

impl Gate {
    /// one_way_gate.gd prepare + create
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let rotation = crate::clouds::option(p, "R")?;
        Ok(Self {
            angle: turn::wrap((rotation.rem_euclid(360.0) * 1000.0).round() as i64),
            opened: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        turn::bounds(self.angle, AREA)
    }
    /// one_way_gate.gd solid_box: the barrier's bounds while standing and closed.
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        if e.status != 1 || self.opened != 0 {
            return None;
        }
        let b = turn::bounds(self.angle, BARRIER);
        Some([
            e.body.x + b[0],
            e.body.y + b[1],
            e.body.x + b[2],
            e.body.y + b[3],
        ])
    }
    /// one_way_gate.gd touches: the turned area.
    pub fn touches(&self, x: i64, y: i64, probe: [i64; 4]) -> bool {
        turn::overlaps(self.angle, AREA, probe, x, y)
    }
    /// one_way_gate.gd tongue: a closed standing barrier stops the tongue (2).
    pub fn tongue(&self, status: i64, at: crate::body::Body, probe: [i64; 4]) -> i64 {
        if status == 1 && self.opened == 0 && turn::overlaps(self.angle, BARRIER, probe, at.x, at.y)
        {
            2
        } else {
            0
        }
    }
    /// one_way_gate.gd projectile_contact for an egg: a thrown egg (mode 1) inside the
    /// entry side opens the gate. The egg always goes on (0).
    pub fn egg_contact(&mut self, e: (i64, i64, i64), egg: crate::Position, thrown: bool) {
        let (status, x, y) = e;
        if status != 1 || self.opened != 0 || !thrown {
            return;
        }
        let probe = [
            egg.x - 12 * S,
            egg.y - 12 * S,
            egg.x + 12 * S,
            egg.y + 12 * S,
        ];
        if turn::overlaps(self.angle, ENTRY, probe, x, y) {
            self.opened = 1;
        }
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "angle" => self.angle,
            "opened" => self.opened,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "angle" => self.angle = value,
            "opened" => self.opened = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (0..turn::TURN).contains(&self.angle) && [0, 1].contains(&self.opened)
    }
}

impl Run {
    /// one_way_gate.gd step: open while a body touches the entry side; close once no
    /// body touches the area. Bodies are the player (unless captured) and actors
    /// (_body_boxes): enemies, o4 stars, o7 eggs and moving pickups, none held.
    pub(crate) fn gate_step(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Gate(g) = &e.kind else {
            return;
        };
        let (x, y, angle, opened) = (e.body.x, e.body.y, g.angle, g.opened != 0);
        let shape = if opened { AREA } else { ENTRY };
        let hit = |b: [i64; 4]| turn::overlaps(angle, shape, b, x, y);
        let mut found = false;
        if self.player.captured_by == 0 {
            let b = self.player.bounds();
            let p = self.player.body;
            found = hit([p.x + b[0], p.y + b[1], p.x + b[2], p.y + b[3]]);
        }
        if !found {
            found = self.entities.iter().any(|o| {
                // one_way_gate.gd _body_boxes: registry enemies (an e33 gust flyer is a
                // walker body but not an enemy), o4, o7, o14 and moving pickups.
                let actor = match &o.kind {
                    Kind::Walker(w) => w.held == 0 && o.is_enemy(),
                    Kind::Star(p) => p.held == 0,
                    Kind::Egg(_) => true,
                    Kind::Pickup(p) => p.held == 0 && p.moving != 0,
                    Kind::Switch(_) => true,
                    _ => false,
                };
                // The turned area stays within 64 px of the gate; bodies 2048 px away
                // cannot reach it with any type's bounds.
                if !actor
                    || o.status != 1
                    || o.collected != 0
                    || (o.body.x - x).abs() > 2048 * S
                    || (o.body.y - y).abs() > 2048 * S
                {
                    return false;
                }
                let b = crate::egg::entity_bounds(o);
                b[0] < b[2]
                    && b[1] < b[3]
                    && hit([
                        o.body.x + b[0],
                        o.body.y + b[1],
                        o.body.x + b[2],
                        o.body.y + b[3],
                    ])
            });
        }
        if let Kind::Gate(g) = &mut self.entities[index].kind {
            if opened != found {
                g.opened = i64::from(found);
            }
        }
    }
}
