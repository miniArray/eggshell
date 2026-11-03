//! hanging_roller.gd (e28): an overhead actor drops, chooses a direction on landing,
//! then rolls (a SHELL-kind weapon). The body lives in `Actor` (ActorKind::Roller).
//! enemy_overlap.gd: the saved entry-contact memory its projectile rule needs.
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{HitKind, Hold},
    entity::{Entity, Kind},
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const HANG: i64 = 0;
pub(crate) const LAUGH: i64 = 1;
pub(crate) const ROLL: i64 = 2;
pub(crate) const BOX: [i64; 4] = [-24 * S, -24 * S, 24 * S, 24 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

/// enemy_overlap.gd FIELDS: the projectile token `a` and the struck token `b`.
#[derive(Clone, Debug, Default)]
pub(crate) struct Overlap {
    pub a: i64,
    pub b: i64,
}
impl Overlap {
    pub fn field(&self, n: &str) -> Option<i64> {
        match n {
            "a" => Some(self.a),
            "b" => Some(self.b),
            _ => None,
        }
    }
    pub fn set_field(&mut self, n: &str, v: i64) -> bool {
        match n {
            "a" => self.a = v,
            "b" => self.b = v,
            _ => return false,
        }
        true
    }
}

impl Actor {
    /// hanging_roller.gd prepare (Options.prepare with one form and no mirror) + create.
    pub fn roller(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || p.mirror != 0 || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e28 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Roller, 0, 0, p.position))
    }
    pub fn roller_valid(&self) -> bool {
        self.variant == 0
            && self.mirror == 0
            && (HANG..=ROLL).contains(&self.mode)
            && (0..=81).contains(&self.timer)
            && [0, 1].contains(&self.landed)
            && self.held == 0
            && self.spat == 0
    }
    /// hanging_roller.gd drop
    fn roller_drop(&mut self) {
        self.mode = ROLL;
        self.timer = 0;
    }
    /// hanging_roller.gd hit with EGG, SPIT or SHELL (CLEAR has no Rust caller; BUMP
    /// and the others do nothing): a hanging roller laughs, then drops.
    pub(crate) fn roller_hit(&mut self) {
        if self.mode != ROLL {
            self.mode = LAUGH;
            self.timer = 81;
        }
    }
}

impl Run {
    /// hanging_roller.gd step.
    pub(crate) fn roller_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            frame,
            camera,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let fresh = w.started == 0;
        if fresh {
            // enemy_body.gd process: the first step's initialisation (mirror is always 0).
            w.started = 1;
            w.impact_cursor = player.impact;
        }
        let step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
        let action = w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        );
        if [Hold::Held, Hold::Gone].contains(&action) {
            return Ok(());
        }
        let p = step.player.body;
        if fresh {
            e.facing = if e.body.x < p.x { 1 } else { -1 };
        }
        if w.mode != ROLL {
            if e.body.y < p.y && (e.body.x - p.x).abs() < 180 * S {
                w.roller_drop();
            } else if w.mode == LAUGH {
                w.timer -= 1;
                if w.timer == 0 {
                    w.roller_drop();
                }
            }
        }
        if w.mode != ROLL {
            return Ok(());
        }
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        body.vx = if w.landed != 0 {
            e.facing * 320 * 60
        } else {
            0
        };
        let distance = body.vx;
        // enemy_motion.gd move (horizontal)
        let (actual, started) = if body.prepare(map, BOX) {
            let support = body.floor(map, BOX);
            let started = support != 0 && body.vy >= 0;
            (
                body.horizontal(map, BOX, distance, support, HorizontalMove::Actor),
                started,
            )
        } else {
            (0, false)
        };
        let landed = w.landed != 0;
        if actual != distance || (landed && self.roller_wall_point(index, map)) {
            // enemy_body.gd strike_wall with Hits.SHELL reaches SOLID 1 types with a
            // `hit`: hard, colour, thorn and item blocks react to EGG only, so nothing
            // changes.
            let e = &mut self.entities[index];
            if e.origin.placed().is_some() {
                e.status = 2;
                e.body.vx = 0;
                e.body.vy = 0;
            } else if let Kind::Walker(w) = &mut e.kind {
                w.remove(&mut e.status, &mut e.can_respawn);
            }
            return Ok(());
        }
        let player_x = self.player.body.x;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if e.body.gravity(map, BOX, started) && w.landed == 0 {
            w.landed = 1;
            e.facing = if e.body.x < player_x { 1 } else { -1 };
        }
        self.hit_others(index, BOX, HitKind::Shell, false)
    }
    /// hanging_roller.gd _wall_point: terrain, a border or a SOLID 1 box at the point 29 px
    /// ahead (inclusive).
    fn roller_wall_point(&self, index: usize, map: &Probe) -> bool {
        let e = &self.entities[index];
        let x = e.body.x + e.facing * 29 * S;
        let y = e.body.y;
        let point = [x, y, x, y];
        // world.gd overlaps_box: borders and solid tiles only.
        if map.border_overlaps(point) || map.terrain_overlaps(point) {
            return true;
        }
        self.entities.iter().enumerate().any(|(i, o)| {
            if i == index || o.status != 1 || held(o) || hidden(o) {
                return false;
            }
            let solid = match &o.kind {
                Kind::Block(b) => b.solid(o),
                Kind::Hard(h) => h.solid(o),
                Kind::Grow(g) => g.solid(o),
                Kind::Post(p) => p.solid(o.body, o.status),
                Kind::Gate(g) => g.solid(o),
                _ => None,
            };
            solid.is_some_and(|b| x >= b[0] && x <= b[2] && y >= b[1] && y <= b[3])
        })
    }
    /// hanging_roller.gd contact.
    pub(crate) fn roller_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        // enemy_body.gd player_overlap
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, BOX), world_box(p, pb));
        if touching {
            if e.body.y > p.y + 8 * S && w.contact == 0 {
                // enemy_body.gd bounce (Moves.bounce).
                self.player.stomp(e.body.vy, input, &mut self.sound);
                if w.mode != ROLL {
                    w.roller_drop();
                }
            } else if e.body.y < p.y + 8 * S {
                let x = e.body.x;
                self.player.hurt(x, &mut self.sound);
            }
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
    /// hanging_roller.gd projectile_contact for a projectile that is not an egg (eggs
    /// call `roller_hit` and get 1): 0 while rolling or already overlapping this
    /// projectile, else the hit and 1 for a spat or rolling projectile, 3 otherwise.
    pub(crate) fn roller_projectile(
        &mut self,
        target: usize,
        projectile_token: i64,
        weapon: bool,
        spat_or_roll: bool,
    ) -> Result<i64, Error> {
        let Kind::Walker(w) = &self.entities[target].kind else {
            return Ok(0);
        };
        if w.mode == ROLL {
            return Ok(0);
        }
        // e6, e8, e11 and e28 weapons (not spat) strike once per entry.
        if weapon && !self.begin_overlap(projectile_token, target)? {
            return Ok(0);
        }
        if let Kind::Walker(w) = &mut self.entities[target].kind {
            w.roller_hit();
        }
        Ok(if spat_or_roll { 1 } else { 3 })
    }
    /// enemy_body.gd begin_overlap: false while an active enemy_overlap pairs these
    /// tokens; otherwise records the pair (registry.gd spawn_dynamic) and is true.
    fn begin_overlap(&mut self, ta: i64, b: usize) -> Result<bool, Error> {
        let tb = self.entities[b].origin.token();
        let Some(a) = self.find_token(ta) else {
            return Ok(false);
        };
        let paired = self.entities.iter().any(|e| {
            e.status == 1 && matches!(&e.kind, Kind::Overlap(o) if o.a == ta && o.b == tb)
        });
        if paired {
            return Ok(false);
        }
        let serial = self.next_serial()?;
        let at = self.entities[a].body;
        let mut row = Entity::dynamic(
            serial,
            Kind::Overlap(Overlap { a: ta, b: tb }),
            Body {
                x: at.x,
                y: at.y,
                ..Body::default()
            },
            -1,
            7,
        );
        row.can_despawn = 0;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(true)
    }
    /// enemy_overlap.gd step: the pair ends when either side is gone, held, hidden or
    /// no longer overlapping.
    pub(crate) fn overlap_step(&mut self, index: usize) {
        let Kind::Overlap(o) = &self.entities[index].kind else {
            return;
        };
        let (a, b) = (self.find_token(o.a), self.find_token(o.b));
        let live = |i: Option<usize>| {
            i.map(|i| &self.entities[i])
                .filter(|e| e.status == 1 && !held(e) && !hidden(e))
        };
        let keep = match (live(a), live(b)) {
            (Some(a), Some(b)) => strict(
                world_box(a.body, crate::egg::entity_bounds(a)),
                world_box(b.body, crate::egg::entity_bounds(b)),
            ),
            _ => false,
        };
        if !keep {
            self.entities[index].status = 3;
        }
    }
}

fn held(e: &Entity) -> bool {
    match &e.kind {
        Kind::Walker(w) => w.held == 1,
        Kind::Pickup(p) => p.held == 1,
        Kind::Star(p) => p.held == 1,
        _ => false,
    }
}
fn hidden(e: &Entity) -> bool {
    matches!(&e.kind, Kind::Walker(w) if w.hidden == 1)
}
