//! soft_walker.gd (e23): a small soft walker that squashes under the player and bursts,
//! knocking nearby soft walkers aside; soft_giant.gd (e24): a large one that bounces a
//! plain landing, bursts into four small walkers under a ground pound, and is shoved by
//! strikes. Both bodies live in `Actor` (ActorKind::SoftWalker and ActorKind::SoftGiant).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    elements::Frozen,
    entity::{Entity, Kind},
    state::Run,
    Error, Placement, Position, SCALE as S,
};
// soft_walker.gd modes.
pub(crate) const WALK: i64 = 0;
pub(crate) const SQUASH: i64 = 1;
pub(crate) const TUMBLE: i64 = 2;
pub(crate) const KNOCKED: i64 = 3;
const KNOCK_SPEED: i64 = 448 * 60;
const KNOCK_TICKS: i64 = 60;
const KNOCK_RANGE: i64 = 128;
const KNOCK_PAUSE: i64 = 2;
const SQUASH_TICKS: i64 = 15;
const WALK_BOX: [i64; 4] = [-14 * S, -14 * S, 14 * S, 16 * S];
const SQUASH_BOX: [i64; 4] = [-14 * S, 2 * S, 14 * S, 16 * S];
const SQUASH_LOW_BOX: [i64; 4] = [-14 * S, 6 * S, 14 * S, 14 * S];
const MAX_SLIDE: i64 = 1024 * 60;
// soft_giant.gd modes.
pub(crate) const GIANT_WAIT: i64 = 0;
pub(crate) const GIANT_WALK: i64 = 1;
pub(crate) const GIANT_PAUSE: i64 = 2;
pub(crate) const GIANT_SQUASH: i64 = 3;
const WAIT_TICKS: i64 = 5;
const PAUSE_TICKS: i64 = 30;
const GIANT_SQUASH_TICKS: i64 = 15;
pub(crate) const GIANT_BOX: [i64; 4] = [-24 * S, -56 * S, 24 * S, 0];
/// soft_giant.gd COPIES: offset from the feet, speed and launch velocity (px, px/s).
const COPIES: [[i64; 4]; 4] = [
    [-32, -16, -320, -416],
    [-16, -32, -256, -480],
    [16, -32, 256, -480],
    [32, -16, 320, -416],
];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}
/// enemy_motion.gd move (horizontal): (actual distance, started on a floor).
fn move_horizontal(body: &mut Body, map: &Probe, b: [i64; 4], distance: i64) -> (i64, bool) {
    if !body.prepare(map, b) {
        return (0, false);
    }
    let support = body.floor(map, b);
    let started = support != 0 && body.vy >= 0;
    (
        body.horizontal(map, b, distance, support, HorizontalMove::Actor),
        started,
    )
}
/// enemy_motion.gd edge
fn edge(body: Body, facing: i64, map: &Probe, b: [i64; 4]) -> bool {
    let left = if facing > 0 { body.x } else { body.x - 12 * S };
    let bottom = body.y + b[3];
    !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S])
}

impl Actor {
    /// soft_walker.gd prepare (Options.prepare with one form) + create.
    pub fn soft_walker(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e23 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::SoftWalker, 0, p.mirror, p.position))
    }
    /// soft_giant.gd prepare (one form; the world compiler lowers the placement 32 px)
    /// + create.
    pub fn soft_giant(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e24 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::SoftGiant, 0, p.mirror, p.position);
        a.mode = GIANT_WAIT;
        a.timer = WAIT_TICKS;
        Ok(a)
    }
    fn slides_valid(&self) -> bool {
        self.slide_from.abs() <= MAX_SLIDE
            && self.slide_to.abs() <= MAX_SLIDE
            && (0..=600).contains(&self.slide_total)
            && (0..=self.slide_total).contains(&self.slide_ticks)
    }
    pub fn soft_walker_valid(&self) -> bool {
        self.variant == 0
            && (WALK..=KNOCKED).contains(&self.mode)
            && (0..=SQUASH_TICKS).contains(&self.timer)
            && self.pin_dx.abs() <= 64 * S
            && self.slides_valid()
    }
    pub fn soft_giant_valid(&self) -> bool {
        self.variant == 0
            && (GIANT_WAIT..=GIANT_SQUASH).contains(&self.mode)
            && (0..=PAUSE_TICKS).contains(&self.timer)
            && self.pin_dx.abs() <= 32 * S
            && self.slides_valid()
    }
    /// soft_walker.gd bounds: the squash's second picture stands 2 px shorter.
    pub(crate) fn soft_bounds(&self) -> [i64; 4] {
        if self.mode != SQUASH {
            WALK_BOX
        } else if self.timer > SQUASH_TICKS - 9 {
            SQUASH_BOX
        } else {
            SQUASH_LOW_BOX
        }
    }
    /// soft_giant.gd height: drawn height in pixels; the squash halves it.
    pub(crate) fn giant_height(&self) -> i64 {
        if self.mode != GIANT_SQUASH {
            64
        } else {
            64 - 32 * (GIANT_SQUASH_TICKS - self.timer) / GIANT_SQUASH_TICKS
        }
    }
    /// soft_walker.gd _hop
    fn soft_hop(&self, body: &mut Body, landed: bool) {
        let speed = (self.slide_from * self.slide_ticks / self.slide_total).abs();
        if landed && speed > 24 * 60 {
            body.vy = -(speed / 2 + 160 * 60);
        }
    }
    /// soft_giant.gd shove
    pub(crate) fn giant_shove(&mut self, direction: i64, ticks: i64) {
        self.slide_from = direction * 512 * 60;
        self.slide_to = direction * 384 * 60;
        self.slide_ticks = ticks;
        self.slide_total = ticks;
    }
    /// soft_walker.gd view_state animation and frame.
    pub fn soft_view(&self) -> (&'static str, Option<i64>) {
        if self.mode == SQUASH {
            ("Squash", Some(i64::from(self.timer <= SQUASH_TICKS / 2)))
        } else {
            ("Walk", None)
        }
    }
}

impl Run {
    /// enemy_body.gd process and the frozen, spit and hazard steps shared by both soft
    /// types. True when the step is over.
    fn soft_begin(&mut self, index: usize, map: &Probe, spits: bool) -> Result<bool, Error> {
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
        if w.started == 0 {
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let mut step = ActorStep {
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
            return Ok(true);
        }
        let b = soft_box(w);
        // element_reactions.gd frozen_step
        match w.frozen_step(&mut e.body, e.status, map, b) {
            Frozen::Free => {}
            Frozen::Done => return Ok(true),
            Frozen::Lava => {
                self.remove_enemy(index)?;
                return Ok(true);
            }
        }
        if spits {
            if let Some(after) = w.spit_step(
                &mut e.body,
                &mut e.facing,
                &mut e.status,
                &mut e.can_respawn,
                &mut step,
            ) {
                if let After::HitOthers(hb) = after {
                    self.hit_others(index, hb, HitKind::Spit, true)?;
                }
                return Ok(true);
            }
        }
        // enemy_body.gd hazards
        if map.lava_overlaps(world_box(e.body, b)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(true);
        }
        Ok(false)
    }
    /// soft_walker.gd step.
    pub(crate) fn soft_walker_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.soft_begin(index, map, true)? {
            return Ok(());
        }
        let Run {
            entities, player, ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        if w.mode == SQUASH {
            body.vx = 0;
            w.timer -= 1;
            if w.timer <= 0 {
                return self.soft_burst(index, map);
            }
            // The body keeps its gravity, so the shorter picture settles 2 px lower.
            body.gravity(map, w.soft_bounds(), false);
            // soft_walker.gd pin
            player.body.x = body.x + w.pin_dx;
            player.body.y = body.y;
            return Ok(());
        }
        let b = w.soft_bounds();
        // A body knocked in this step's earlier burst still takes its own step now.
        let pending = w.mode == KNOCKED && w.timer > 0 && w.slide_ticks > 0;
        if w.mode == KNOCKED && !pending {
            Self::soft_knocked(w, body, &mut e.facing, player.body.x, map, b);
            return Ok(());
        }
        if pending {
            w.timer = 0;
        }
        let grounded = body.floor(map, b) != 0;
        if w.slide_ticks > 0 && !pending {
            body.vx = w.slide_from * w.slide_ticks / w.slide_total;
            w.slide_ticks -= 1;
        } else if w.mode == WALK || pending {
            let wet = i64::from(map.water_overlaps(world_box(*body, b)));
            body.vx = e.facing * 48 * 60 / (wet + 1);
            if grounded && edge(*body, e.facing, map, b) {
                e.facing = -e.facing;
                body.vx = -body.vx;
            }
        } else {
            body.vx = 0;
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = move_horizontal(body, map, b, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
                w.slide_from = -w.slide_from;
            }
        }
        let landed = body.gravity(map, b, started);
        if landed && w.mode == TUMBLE {
            w.mode = WALK;
        }
        if pending {
            w.soft_hop(body, landed);
        }
        Ok(())
    }
    /// soft_walker.gd _knocked_step
    fn soft_knocked(
        w: &mut Actor,
        body: &mut Body,
        facing: &mut i64,
        player_x: i64,
        map: &Probe,
        b: [i64; 4],
    ) {
        if w.slide_ticks == 0 {
            body.vx = 0;
            body.gravity(map, b, false);
            w.timer -= 1;
            if w.timer <= 0 {
                w.timer = 0;
                w.mode = WALK;
                if body.x != player_x {
                    *facing = if body.x > player_x { -1 } else { 1 };
                }
            }
            return;
        }
        let speed = w.slide_from * w.slide_ticks / w.slide_total;
        w.slide_ticks -= 1;
        body.vx = speed;
        let mut started = false;
        if speed != 0 {
            let (actual, on_floor) = move_horizontal(body, map, b, speed);
            started = on_floor;
            if actual != speed && speed.abs() > 64 * 60 {
                *facing = -speed.signum();
                w.slide_from = *facing * 48 * 60;
                w.slide_total = 90;
                w.slide_ticks = 89;
            }
        }
        let landed = body.gravity(map, b, started);
        w.soft_hop(body, landed);
        if w.slide_ticks == 0 {
            w.timer = KNOCK_PAUSE;
        }
    }
    /// soft_walker.gd burst: knocks soft walkers within 128 px aside, then removes the
    /// body.
    fn soft_burst(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let at = self.entities[index].body;
        for other in 0..self.entities.len() {
            if other == index {
                continue;
            }
            let later = other > index;
            let o = &mut self.entities[other];
            let Kind::Walker(ow) = &mut o.kind else {
                continue;
            };
            // soft_walker.gd _knockable
            if !(ow.kind == ActorKind::SoftWalker
                && o.status == 1
                && [WALK, TUMBLE, KNOCKED].contains(&ow.mode)
                && ow.held == 0
                && ow.spat == 0
                && ow.hidden == 0
                && ow.frozen == 0)
                || o.body.x == at.x
                || (o.body.y - at.y).abs() >= KNOCK_RANGE * S
                || (o.body.x - at.x).abs() >= KNOCK_RANGE * S
            {
                continue;
            }
            ow.mode = KNOCKED;
            ow.slide_from = KNOCK_SPEED * if o.body.x > at.x { 1 } else { -1 };
            ow.slide_total = KNOCK_TICKS;
            ow.slide_ticks = KNOCK_TICKS;
            ow.timer = i64::from(later);
            if !later {
                let grounded = o.body.floor(map, ow.soft_bounds()) != 0;
                ow.soft_hop(&mut o.body, grounded);
            }
        }
        let e = &mut self.entities[index];
        if let Kind::Walker(w) = &mut e.kind {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
    /// soft_walker.gd contact.
    pub(crate) fn soft_walker_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.mode == SQUASH {
            // The hold puts the player back after its own move in this step.
            self.player.body.x = e.body.x + w.pin_dx;
            self.player.body.y = e.body.y;
            return;
        }
        if ![WALK, KNOCKED].contains(&w.mode) {
            w.contact = 0;
            return;
        }
        // enemy_body.gd player_overlap
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, w.soft_bounds()), world_box(p, pb));
        let mut hurt = false;
        if touching && w.contact == 0 {
            if e.body.y > p.y - 8 * S {
                w.mode = SQUASH;
                w.timer = SQUASH_TICKS;
                e.body.vx = 0;
                w.pin_dx = (p.x - e.body.x).clamp(-64 * S, 64 * S);
                self.player.body.x = e.body.x + w.pin_dx;
                self.player.body.y = e.body.y;
            } else {
                hurt = true;
            }
        } else if touching && e.body.y < p.y - 8 * S {
            hurt = true;
        }
        w.contact = i64::from(touching);
        if hurt {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
    /// soft_giant.gd step.
    pub(crate) fn soft_giant_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.soft_begin(index, map, false)? {
            return Ok(());
        }
        let Run {
            entities, player, ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        if w.mode == GIANT_SQUASH {
            body.vx = 0;
            w.timer -= 1;
            Self::giant_pin(w, *body, player);
            if w.timer <= 0 {
                return self.giant_burst(index);
            }
            return Ok(());
        }
        if [GIANT_WAIT, GIANT_PAUSE].contains(&w.mode) {
            w.timer -= 1;
            if w.timer <= 0 {
                w.mode = if w.mode == GIANT_WAIT {
                    GIANT_WALK
                } else {
                    GIANT_WAIT
                };
                w.timer = if w.mode == GIANT_WAIT { WAIT_TICKS } else { 0 };
            }
        }
        let b = GIANT_BOX;
        let grounded = body.floor(map, b) != 0;
        if w.slide_ticks > 0 {
            let done = w.slide_total - w.slide_ticks;
            body.vx = w.slide_from + (w.slide_to - w.slide_from) * done / w.slide_total;
            w.slide_ticks -= 1;
        } else if w.mode == GIANT_WALK {
            let wet = i64::from(map.water_overlaps(world_box(*body, b)));
            body.vx = e.facing * 48 * 60 / (wet + 1);
            if grounded && edge(*body, e.facing, map, b) {
                e.facing = -e.facing;
                body.vx = -body.vx;
            }
        } else {
            body.vx = 0;
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = move_horizontal(body, map, b, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
                w.slide_from = -w.slide_from;
                w.slide_to = -w.slide_to;
            }
        }
        body.gravity(map, b, started);
        Ok(())
    }
    /// soft_giant.gd pin: the player stands on the squashing top.
    fn giant_pin(w: &Actor, body: Body, player: &mut crate::player::Player) {
        player.body.x = body.x + w.pin_dx;
        player.body.y = body.y - (w.giant_height() - 4) * S;
        player.body.vx = 0;
        player.body.vy = 0;
        player.on_floor = 1;
    }
    /// soft_giant.gd burst: removed, then four tumbling e23 copies (registry.gd
    /// spawn_dynamic with soft_walker.gd tumble_options).
    fn giant_burst(&mut self, index: usize) -> Result<(), Error> {
        let e = &mut self.entities[index];
        let at = e.body;
        if let Kind::Walker(w) = &mut e.kind {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        for [dx, dy, speed, vy] in COPIES {
            let serial = self.next_serial()?;
            let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
            let position = Position {
                x: at.x + dx * S,
                y: at.y + dy * S,
            };
            let mut copy = Actor::new(ActorKind::SoftWalker, 0, 0, position);
            copy.mode = TUMBLE;
            copy.slide_from = speed * 60;
            copy.slide_ticks = 30;
            copy.slide_total = 30;
            let mut row = Entity::dynamic(
                serial,
                Kind::Walker(Box::new(copy)),
                Body {
                    x: position.x,
                    y: position.y,
                    vx: 0,
                    vy: vy * 60,
                },
                speed.signum(),
                8,
            );
            row.family_index = family;
            self.dynamic_serial = serial + 1;
            self.entities.push(row);
        }
        Ok(())
    }
    /// soft_giant.gd contact.
    pub(crate) fn soft_giant_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.mode == GIANT_SQUASH {
            return;
        }
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, GIANT_BOX), world_box(p, pb));
        let mut hurt = false;
        if touching && w.contact == 0 && e.body.y > p.y + 24 * S {
            if pounding {
                w.mode = GIANT_SQUASH;
                w.timer = GIANT_SQUASH_TICKS;
                e.body.vx = 0;
                w.slide_ticks = 0;
                w.pin_dx = (p.x - e.body.x).clamp(-32 * S, 32 * S);
                Self::giant_pin(w, e.body, &mut self.player);
            } else {
                let velocity = -(e.body.vy / 2).abs() - 336 * 60;
                self.player.bounce(velocity, input, &mut self.sound);
                w.mode = GIANT_PAUSE;
                w.timer = PAUSE_TICKS;
                e.body.vx = 0;
            }
        } else if touching && e.body.y < p.y + 24 * S {
            hurt = true;
        }
        let e = &mut self.entities[index];
        if let Kind::Walker(w) = &mut e.kind {
            w.contact = i64::from(touching);
        }
        if hurt {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
    /// soft_walker.gd / soft_giant.gd hit with a non-element kind from `from_x`: a small
    /// walker is removed unless squashing; a giant is shoved for 6 ticks.
    pub(crate) fn soft_hit(&mut self, index: usize, from_x: i64) {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        match w.kind {
            ActorKind::SoftWalker if w.mode != SQUASH => {
                w.remove(&mut e.status, &mut e.can_respawn)
            }
            ActorKind::SoftGiant if w.mode != GIANT_SQUASH => {
                w.giant_shove(if from_x < e.body.x { 1 } else { -1 }, 6)
            }
            _ => {}
        }
    }
    /// soft_walker.gd / soft_giant.gd projectile_contact for a projectile at `from_x`
    /// (an egg travelling at `egg_vx`, None for a spit or shell): 0 while squashing.
    pub(crate) fn soft_projectile(
        &mut self,
        index: usize,
        from_x: i64,
        egg_vx: Option<i64>,
    ) -> i64 {
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return 0;
        };
        match w.kind {
            ActorKind::SoftWalker => {
                if w.mode == SQUASH {
                    return 0;
                }
                w.remove(&mut e.status, &mut e.can_respawn);
                3
            }
            _ => {
                if w.mode == GIANT_SQUASH {
                    return 0;
                }
                let direction = if from_x < e.body.x { 1 } else { -1 };
                match egg_vx {
                    Some(travel) => {
                        w.giant_shove(
                            if travel != 0 {
                                travel.signum()
                            } else {
                                direction
                            },
                            48,
                        );
                        1
                    }
                    None => {
                        w.giant_shove(direction, 6);
                        3
                    }
                }
            }
        }
    }
}

/// The current collision box of a soft body (soft_walker.gd / soft_giant.gd bounds).
fn soft_box(w: &Actor) -> [i64; 4] {
    if w.kind == ActorKind::SoftGiant {
        GIANT_BOX
    } else {
        w.soft_bounds()
    }
}
