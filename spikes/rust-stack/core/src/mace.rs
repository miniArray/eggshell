//! mace_walker.gd (e27): a walker that conjures a spiked ball and hurls it at a level
//! player; an egg sets it rolling away, and a rolling walker breaks on walls and on the
//! player. mace_ball.gd (enemy_mace): the ball, which grows in the thrower's hands,
//! flies straight once thrown and drops when the thrower lets go. Both bodies live in
//! `Actor` (ActorKind::Mace and ActorKind::MaceBall).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{HitKind, Hold},
    elements::Frozen,
    entity::{Entity, Kind},
    petal::polygon_overlap,
    state::Run,
    Error, Placement, Position, SCALE as S,
};
// mace_walker.gd modes.
pub(crate) const WALK: i64 = 0;
pub(crate) const CONJURE: i64 = 1;
pub(crate) const AIM: i64 = 2;
pub(crate) const THROW: i64 = 3;
pub(crate) const ROLL: i64 = 4;
pub(crate) const LOFT: i64 = 5;
const CONJURE_TICKS: i64 = 45;
const AIM_TICKS: i64 = 24;
const COOLDOWN: i64 = 120;
const ROLL_GRACE: i64 = 15;
pub(crate) const WALK_BOX: [i64; 4] = [-14 * S, -14 * S, 14 * S, 16 * S];
pub(crate) const ROLL_BOX: [i64; 4] = [-14 * S, -12 * S, 14 * S, 16 * S];
// mace_ball.gd modes.
pub(crate) const HELD: i64 = 0;
pub(crate) const FLYING: i64 = 1;
pub(crate) const LOOSE: i64 = 2;
const SPEED: i64 = 256 * 60;
/// mace_ball.gd HULL: an octagon at full size (radius 16 px).
const HULL: [[i64; 2]; 8] = [
    [-12, -12],
    [0, -16],
    [12, -12],
    [16, 0],
    [12, 12],
    [0, 16],
    [-12, 12],
    [-16, 0],
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
    /// mace_walker.gd prepare (Options.prepare with one form) + create.
    pub fn mace(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e27 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Mace, 0, p.mirror, p.position))
    }
    pub fn mace_valid(&self) -> bool {
        self.variant == 0
            && (WALK..=LOFT).contains(&self.mode)
            && (0..=CONJURE_TICKS + AIM_TICKS).contains(&self.throw_tick)
            && [-1, 1].contains(&self.aim)
            && self.ball_token >= 0
            && (0..=COOLDOWN).contains(&self.cooldown)
            && (0..=ROLL_GRACE).contains(&self.grace)
            && [0, 1].contains(&self.bounced)
            && [0, 1].contains(&self.grounded)
            && [0, 1].contains(&self.contact)
    }
    pub fn mace_ball_valid(&self) -> bool {
        (HELD..=LOOSE).contains(&self.mode)
            && self.owner_token >= 0
            && [-1, 1].contains(&self.aim)
            && (0..=12).contains(&self.lift)
            && (0..=CONJURE_TICKS).contains(&self.growth)
    }
    /// mace_walker.gd bounds
    pub(crate) fn mace_bounds(&self) -> [i64; 4] {
        if self.mode == ROLL {
            ROLL_BOX
        } else {
            WALK_BOX
        }
    }
    /// mace_ball.gd scale_of: 4 px to 64 px over the conjuring time.
    fn ball_scale(&self) -> i64 {
        3 + (CONJURE_TICKS - 3) * self.growth / CONJURE_TICKS
    }
    /// mace_ball.gd bounds
    pub(crate) fn ball_bounds(&self) -> [i64; 4] {
        let radius = 16 * S * self.ball_scale() / CONJURE_TICKS;
        [-radius, -radius, radius, radius]
    }
    /// mace_ball.gd view_state size (px).
    pub(crate) fn ball_size(&self) -> f64 {
        64.0 * self.ball_scale() as f64 / CONJURE_TICKS as f64
    }
    /// mace_walker.gd view_state animation.
    pub(crate) fn mace_animation(&self) -> &'static str {
        [
            "Walk",
            "CreateSpikeball",
            "PrepareThrow",
            "Throw",
            "Roll",
            "Walk",
        ][self.mode as usize]
    }
}

impl Run {
    fn mace_actor(&mut self, index: usize) -> &mut Actor {
        let Kind::Walker(w) = &mut self.entities[index].kind else {
            unreachable!()
        };
        w
    }
    /// mace_walker.gd ball: the held ball of the walker at `index`, if it still is one.
    fn held_ball(&self, index: usize) -> Option<usize> {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return None;
        };
        if w.ball_token == 0 {
            return None;
        }
        let owner = e.origin.token();
        self.find_token(w.ball_token).filter(|&i| {
            let b = &self.entities[i];
            matches!(&b.kind, Kind::Walker(bw) if bw.owner_token == owner) && b.status == 1
        })
    }
    /// mace_walker.gd _drop_ball: the held ball falls loose.
    fn mace_drop_ball(&mut self, index: usize) {
        if let Some(i) = self.held_ball(index) {
            let b = &mut self.entities[i];
            if let Kind::Walker(bw) = &mut b.kind {
                bw.mode = LOOSE;
                bw.owner_token = 0;
            }
            b.body.vx = 0;
            b.body.vy = 0;
        }
        self.mace_actor(index).ball_token = 0;
    }
    /// mace_walker.gd on_remove (enemy_body.gd remove runs it before the status
    /// changes): Actor::remove marks a removed walker, and this drops its ball. The
    /// dispatch loops call it after every step and contact, before anything reads the
    /// ball again.
    pub(crate) fn mace_on_remove(&mut self) {
        // The mace walkers' rows, in table order, rebuilt when the table length changed
        // or a remembered row no longer holds one (scanning the whole table after every
        // dispatch made big levels quadratic).
        let is_mace = |e: &crate::entity::Entity| matches!(&e.kind, Kind::Walker(w) if w.kind == ActorKind::Mace);
        let stale = self.mace_rows.0 != self.entities.len()
            || self
                .mace_rows
                .1
                .iter()
                .any(|&i| !self.entities.get(i).is_some_and(is_mace));
        if stale {
            self.mace_rows = (
                self.entities.len(),
                (0..self.entities.len())
                    .filter(|&i| is_mace(&self.entities[i]))
                    .collect(),
            );
        }
        let rows = self.mace_rows.1.clone();
        for index in rows {
            let pending = matches!(&self.entities[index].kind,
                Kind::Walker(w) if w.kind == ActorKind::Mace && w.drop_pending != 0);
            if pending {
                self.mace_actor(index).drop_pending = 0;
                self.mace_drop_ball(index);
            }
        }
    }
    /// mace_walker.gd roll
    fn mace_roll(&mut self, index: usize, direction: i64, vy: i64) {
        self.mace_drop_ball(index);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        w.mode = ROLL;
        e.facing = direction;
        e.body.vx = direction * 432 * 60;
        e.body.vy = vy;
        w.grace = ROLL_GRACE;
        w.grounded = 0;
    }
    /// mace_walker.gd step.
    pub(crate) fn mace_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        if action == Hold::Held {
            self.mace_drop_ball(index);
            return Ok(());
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        // element_reactions.gd frozen_step
        match w.frozen_step(&mut e.body, e.status, map, w.mace_bounds()) {
            Frozen::Free => {}
            Frozen::Done => return Ok(()),
            Frozen::Lava => {
                self.remove_enemy(index)?;
                self.mace_on_remove();
                return Ok(());
            }
        }
        if action == Hold::Gone {
            return Ok(());
        }
        if action == Hold::Released {
            let e = &mut self.entities[index];
            let Kind::Walker(w) = &mut e.kind else {
                unreachable!()
            };
            w.spat = 0;
            let direction = if self.player.facing != 0 {
                self.player.facing
            } else {
                1
            };
            if e.body.vx == 0 {
                // Spat upward: a high arc that knocks over what it meets.
                w.mode = LOFT;
                e.facing = direction;
                e.body.vx = direction * (256 * 60 + self.player.body.vx.abs());
                e.body.vy = -768 * 60;
                w.grounded = 0;
            } else {
                self.mace_roll(index, direction, -256 * 60);
            }
        }
        // enemy_body.gd hazards
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if map.lava_overlaps(world_box(e.body, w.mace_bounds())) {
            w.remove(&mut e.status, &mut e.can_respawn);
            self.mace_on_remove();
            return Ok(());
        }
        w.cooldown = (w.cooldown - 1).max(0);
        w.grace = (w.grace - 1).max(0);
        match w.mode {
            WALK => self.mace_walk(index, map)?,
            CONJURE | AIM => {
                e.body.vx = 0;
                w.throw_tick += 1;
                if w.throw_tick == CONJURE_TICKS {
                    w.mode = AIM;
                } else if w.throw_tick >= CONJURE_TICKS + AIM_TICKS {
                    self.mace_throw(index);
                }
            }
            ROLL => e.body.vx = e.facing * 432 * 60,
            _ => {}
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let b = w.mace_bounds();
        let body = &mut e.body;
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = move_horizontal(body, map, b, distance);
            started = on_floor;
            if actual != distance {
                if w.mode == ROLL {
                    w.remove(&mut e.status, &mut e.can_respawn);
                    self.mace_on_remove();
                    return Ok(());
                }
                if w.mode == WALK {
                    e.facing = -e.facing;
                }
                body.vx = 0;
            }
        }
        let mut landed = body.gravity(map, b, started);
        if landed && w.grounded == 0 {
            if w.mode == THROW {
                w.mode = WALK;
                w.cooldown = COOLDOWN;
            } else if w.mode == LOFT {
                w.mode = WALK;
                body.vx = 0;
            } else if w.mode == ROLL && w.bounced == 0 {
                body.vy = -384 * 60;
                w.bounced = 1;
                landed = false;
            }
        }
        w.grounded = i64::from(landed || body.floor(map, b) != 0);
        if [ROLL, LOFT].contains(&w.mode) && e.status == 1 {
            self.hit_others(index, b, HitKind::Spit, false)?;
            self.mace_on_remove();
        }
        Ok(())
    }
    /// mace_walker.gd _walk
    fn mace_walk(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let (px, py) = (self.player.body.x, self.player.body.y);
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let wet = i64::from(map.water_overlaps(world_box(e.body, WALK_BOX)));
        e.body.vx = e.facing * 48 * 60 / (wet + 1);
        if w.grounded != 0 && edge(e.body, e.facing, map, WALK_BOX) {
            e.facing = -e.facing;
            e.body.vx = -e.body.vx;
        }
        let facing_player = (e.facing < 0 && e.body.x > px) || (e.facing > 0 && e.body.x < px);
        if w.cooldown == 0
            && facing_player
            && e.body.y < py + 64 * S
            && e.body.y > py - 116 * S
            && !captured
        {
            self.mace_conjure(index)?;
        }
        Ok(())
    }
    /// mace_walker.gd _conjure: registry.gd spawn_dynamic of the enemy_mace ball.
    fn mace_conjure(&mut self, index: usize) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        w.mode = CONJURE;
        e.body.vx = 0;
        w.throw_tick = 0;
        w.aim = -e.facing;
        let at = Position {
            x: e.body.x - 4 * S * w.aim,
            y: e.body.y - 2 * S,
        };
        let aim = w.aim;
        let serial = self.next_serial()?;
        let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
        let mut ball = Actor::new(ActorKind::MaceBall, 0, 0, at);
        ball.owner_token = token;
        ball.aim = aim;
        let mut row = Entity::dynamic(
            serial,
            Kind::Walker(Box::new(ball)),
            Body {
                x: at.x,
                y: at.y,
                ..Body::default()
            },
            -1,
            8,
        );
        row.family_index = family;
        row.can_despawn = 1;
        let ball_token = row.origin.token();
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        self.mace_actor(index).ball_token = ball_token;
        Ok(())
    }
    /// mace_walker.gd _throw: the held ball flies; the walker hops back.
    fn mace_throw(&mut self, index: usize) {
        if let Some(i) = self.held_ball(index) {
            if let Kind::Walker(bw) = &mut self.entities[i].kind {
                bw.mode = FLYING;
                bw.owner_token = 0;
                bw.lift = 12;
            }
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        w.ball_token = 0;
        w.mode = THROW;
        e.body.vy = -192 * 60;
        e.body.vx = 48 * 60 * w.aim;
        w.grounded = 0;
    }
    /// mace_walker.gd contact.
    pub(crate) fn mace_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        // enemy_body.gd player_overlap
        let touching = !(w.hidden != 0 || w.held != 0 || w.spat != 0 || e.status != 1 || captured)
            && strict(world_box(e.body, w.mace_bounds()), world_box(p, pb));
        let (mut hurt, mut bounce) = (false, false);
        if [ROLL, LOFT].contains(&w.mode) {
            if touching && w.mode == ROLL && w.grace == 0 {
                w.remove(&mut e.status, &mut e.can_respawn);
            }
        } else if touching && e.body.y > p.y - 8 * S {
            if w.contact == 0 {
                bounce = !pounding;
                w.remove(&mut e.status, &mut e.can_respawn);
            }
        } else if touching {
            hurt = true;
        }
        w.contact = i64::from(touching);
        let (x, vy) = (e.body.x, e.body.vy);
        if bounce {
            self.player.stomp(vy, input, &mut self.sound);
        }
        if hurt {
            self.player.hurt(x, &mut self.sound);
        }
        self.mace_on_remove();
    }
    /// mace_walker.gd hit with a non-element kind: removed.
    pub(crate) fn mace_hit(&mut self, index: usize) {
        let e = &mut self.entities[index];
        if let Kind::Walker(w) = &mut e.kind {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        self.mace_on_remove();
    }
    /// mace_walker.gd projectile_contact: an egg is used up and sends the walker rolling
    /// away from it (1); any other projectile removes it (3).
    pub(crate) fn mace_projectile(&mut self, index: usize, from_x: i64, egg: bool) -> i64 {
        if !egg {
            self.mace_hit(index);
            return 3;
        }
        let direction = if self.entities[index].body.x > from_x {
            1
        } else {
            -1
        };
        self.mace_roll(index, direction, 0);
        1
    }
    /// mace_ball.gd step.
    pub(crate) fn mace_ball_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
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
        if action == Hold::Gone {
            return Ok(());
        }
        let mode = w.mode;
        match mode {
            HELD => {
                let owner_token = w.owner_token;
                let owner = self.find_token(owner_token).and_then(|i| {
                    let o = &self.entities[i];
                    match &o.kind {
                        Kind::Walker(ow)
                            if o.status == 1
                                && ow.kind == ActorKind::Mace
                                && ow.ball_token == token =>
                        {
                            Some((ow.throw_tick, ow.aim, o.body))
                        }
                        _ => None,
                    }
                });
                let e = &mut self.entities[index];
                let Kind::Walker(w) = &mut e.kind else {
                    unreachable!()
                };
                let Some((tick, aim, owner_body)) = owner else {
                    w.mode = LOOSE;
                    w.owner_token = 0;
                    return Ok(());
                };
                // mace_ball.gd _follow: rise to the hand, then swing back over the head.
                w.growth = tick.min(CONJURE_TICKS);
                let (dx, dy) = if tick <= CONJURE_TICKS {
                    (
                        -4 * S - 18 * S * tick / CONJURE_TICKS,
                        -2 * S - 22 * S * tick / CONJURE_TICKS,
                    )
                } else {
                    let swing = tick - CONJURE_TICKS;
                    let half = AIM_TICKS / 2;
                    let along = if swing <= half {
                        swing
                    } else {
                        AIM_TICKS - swing
                    };
                    (
                        -22 * S + 32 * S * swing / AIM_TICKS,
                        -24 * S - 12 * S * along / half,
                    )
                };
                e.body.x = owner_body.x + dx * aim;
                e.body.y = owner_body.y + dy;
            }
            FLYING => {
                e.body.x -= w.aim * SPEED;
                if w.lift > 0 {
                    w.lift -= 1;
                    e.body.y -= S;
                }
            }
            _ => {
                let body = &mut e.body;
                if body.vx > 0 {
                    body.vx = (body.vx - 1296).max(0);
                } else if body.vx < 0 {
                    body.vx = (body.vx + 1296).min(0);
                }
                let b = w.ball_bounds();
                let distance = body.vx;
                let mut started = false;
                if distance != 0 {
                    let (actual, on_floor) = move_horizontal(body, map, b, distance);
                    started = on_floor;
                    if actual != distance {
                        body.vx = 0;
                    }
                }
                body.gravity(map, b, started);
            }
        }
        Ok(())
    }
    /// mace_ball.gd contact: touching the hull hurts.
    pub(crate) fn mace_ball_contact(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        if e.status != 1 || self.player.captured_by != 0 {
            return;
        }
        let scale = w.ball_scale();
        let hull: Vec<Position> = HULL
            .iter()
            .map(|[x, y]| Position {
                x: e.body.x + x * S * scale / CONJURE_TICKS,
                y: e.body.y + y * S * scale / CONJURE_TICKS,
            })
            .collect();
        let pb = self.player.bounds();
        if polygon_overlap(&hull, world_box(self.player.body, pb)) {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}
